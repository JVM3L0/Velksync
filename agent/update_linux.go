package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

// Instalação da atualização no Linux: o pacote assinado é conferido em
// memória, o binário novo é testado ao lado do atual e só então renomeado por
// cima (atômico; o processo em execução não é afetado até reiniciar). O
// anterior fica em "<binário>.old".

const presenceBinary = "/usr/local/bin/velksync-agent"

// updateTarget é o binário em execução, se dá para trocá-lo sem root.
func updateTarget() (string, error) {
	if runtime.GOARCH != "amd64" {
		return "", fmt.Errorf("não há pacote para %s", runtime.GOARCH)
	}
	exe, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("não achei o binário do agente: %w", err)
	}
	f, err := os.CreateTemp(filepath.Dir(exe), ".velksync-*")
	if err != nil {
		return "", fmt.Errorf("sem permissão para trocar %s", exe)
	}
	f.Close()
	os.Remove(f.Name())
	return exe, nil
}

// fetchLinuxBinary baixa o pacote da release, confere e devolve o binário.
func (u *updater) fetchLinuxBinary(r releaseInfo) ([]byte, error) {
	data, err := u.fetchVerified(r, "velksync-agent-"+r.Tag+"-linux-amd64.tar.gz")
	if err != nil {
		return nil, err
	}
	return extractAgent(data)
}

func extractAgent(archive []byte) ([]byte, error) {
	gz, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return nil, fmt.Errorf("pacote inválido: %w", err)
	}
	tr := tar.NewReader(gz)
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil, errors.New("o pacote não tem o velksync-agent")
		}
		if err != nil {
			return nil, fmt.Errorf("pacote inválido: %w", err)
		}
		if h.Typeflag != tar.TypeReg || path.Clean(h.Name) != "velksync-agent" {
			continue
		}
		if h.Size > maxSetupBytes {
			return nil, errors.New("binário grande demais")
		}
		bin, err := io.ReadAll(tr)
		if err != nil {
			return nil, fmt.Errorf("pacote incompleto: %w", err)
		}
		return bin, nil
	}
}

// runNew roda o binário recém-gravado. Um processo criado por outra parte do
// agente nesse instante segura o arquivo aberto por um momento ("text file
// busy", golang/go#22315), então vale insistir.
func runNew(ctx context.Context, path string) (out []byte, err error) {
	for attempt := 1; ; attempt++ {
		out, err = exec.CommandContext(ctx, path, "-h").CombinedOutput()
		if attempt == 10 || !errors.Is(err, syscall.ETXTBSY) {
			return out, err
		}
		time.Sleep(time.Duration(attempt) * 20 * time.Millisecond)
	}
}

// replaceBinary grava o binário novo, roda para ver se funciona neste PC e se
// é mesmo a versão esperada, e troca o antigo.
func replaceBinary(target string, bin []byte, want string) error {
	// Já instalado (faltou só reiniciar): não perder a cópia da anterior.
	if cur, err := os.ReadFile(target); err == nil && bytes.Equal(cur, bin) {
		return nil
	}
	f, err := os.CreateTemp(filepath.Dir(target), ".velksync-*")
	if err != nil {
		return fmt.Errorf("não consegui gravar: %w", err)
	}
	tmp := f.Name()
	defer os.Remove(tmp) // depois do rename não existe mais
	_, err = f.Write(bin)
	if err == nil {
		err = f.Chmod(0o755)
	}
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return fmt.Errorf("não consegui gravar (disco cheio?): %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	out, err := runNew(ctx, tmp)
	if err != nil {
		return fmt.Errorf("a versão nova não roda neste PC: %w", err)
	}
	if first, _, _ := strings.Cut(string(out), "\n"); first != "velksync-agent "+want {
		return fmt.Errorf("o pacote não traz a versão %s", want)
	}

	old := target + ".old"
	os.Remove(old)
	if err := os.Link(target, old); err != nil {
		return fmt.Errorf("não consegui guardar a versão atual: %w", err)
	}
	if err := os.Rename(tmp, target); err != nil {
		return fmt.Errorf("não consegui trocar o binário: %w", err)
	}
	return nil
}

// hasPresence diz se o serviço de presença foi instalado (cópia do root).
func hasPresence() bool {
	_, err := os.Stat(presenceBinary)
	return err == nil
}

// updatePresence troca a cópia do root. O binário vai pela entrada padrão, a
// partir da memória, e o hash é conferido já como root: nada que outro
// processo do usuário possa trocar no caminho.
func updatePresence(bin []byte) error {
	const script = `set -e
umask 022
new="$1.new"
trap 'rm -f "$new"' EXIT
cat > "$new"
echo "$2  $new" | sha256sum -c --status -
chmod 755 "$new"
mv -f "$new" "$1"
systemctl try-restart velksync-presence`
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "pkexec", "/bin/sh", "-c", script, "velksync", presenceBinary,
		fmt.Sprintf("%x", sha256.Sum256(bin)))
	cmd.Stdin = bytes.NewReader(bin)
	out, err := cmd.CombinedOutput()
	var exit *exec.ExitError
	switch {
	case err == nil:
		return nil
	case errors.Is(err, exec.ErrNotFound):
		return errors.New("este sistema não tem o pkexec")
	case ctx.Err() != nil:
		return errors.New("a senha não foi informada a tempo")
	case errors.As(err, &exit) && exit.ExitCode() == 126:
		return errors.New("o pedido de senha foi cancelado")
	case errors.As(err, &exit) && exit.ExitCode() == 127:
		return errors.New("não foi possível pedir a senha")
	}
	return fmt.Errorf("a troca falhou: %s", strings.TrimSpace(string(out)))
}

func inAgentUnit(cgroup string) bool {
	for _, line := range strings.Split(cgroup, "\n") {
		if strings.HasSuffix(line, "/velksync-agent.service") {
			return true
		}
	}
	return false
}

// restartAgent pede ao systemd para subir o binário novo.
func restartAgent() error {
	// INVOCATION_ID é herdado por terminais e outros serviços; o cgroup não.
	cgroup, err := os.ReadFile("/proc/self/cgroup")
	if err != nil || !inAgentUnit(string(cgroup)) {
		return errors.New("feche e abra o agente (ele não está rodando pelo systemd)")
	}
	out, err := exec.Command("systemctl", "--user", "--no-block", "restart", "velksync-agent").CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemctl: %s", strings.TrimSpace(string(out)))
	}
	return nil
}
