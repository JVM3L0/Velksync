package main

import (
	"context"
	"log"
	"net/http"
	"slices"
	"strings"
	"time"
)

type ctxKey int

const (
	authKey ctxKey = iota
	clientKey
)

func authOf(r *http.Request) authResult {
	a, _ := r.Context().Value(authKey).(authResult)
	return a
}

// clientOf identifica quem fez o pedido: o id do celular ou "master" (CLI).
func clientOf(r *http.Request) string {
	c, _ := r.Context().Value(clientKey).(string)
	return c
}

func (s *Server) isRevoked(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Contains(s.cfg.Revoked, id)
}

func (s *Server) addDevice(id, name string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cfg.Devices = append(s.cfg.Devices, PairedDevice{ID: id, Name: name, PairedAt: time.Now()})
	s.persist()
}

// revoke aceita o id ou o nome do celular e devolve os ids revogados.
func (s *Server) revoke(target string) []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	var ids []string
	keep := s.cfg.Devices[:0]
	for _, d := range s.cfg.Devices {
		if d.ID == target || strings.EqualFold(d.Name, target) {
			ids = append(ids, d.ID)
			continue
		}
		keep = append(keep, d)
	}
	s.cfg.Devices = keep
	// Um id que não está na lista (pareado no outro sistema do dual boot)
	// também pode ser revogado direto.
	if len(ids) == 0 && len(target) == 16 {
		ids = []string{target}
	}
	for _, id := range ids {
		if !slices.Contains(s.cfg.Revoked, id) {
			s.cfg.Revoked = append(s.cfg.Revoked, id)
		}
	}
	if len(ids) > 0 {
		s.persist()
	}
	return ids
}

// persist grava a config; chamar com s.mu travado.
func (s *Server) persist() {
	if s.configPath == "" {
		return
	}
	if err := saveConfig(s.configPath, s.cfg); err != nil {
		log.Printf("falha ao salvar a config: %v", err)
	}
}

// masterOnly restringe a rota aos comandos rodados no próprio PC.
func masterOnly(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if authOf(r) != authMaster {
			writeErr(w, http.StatusForbidden, "só pode ser usado no próprio PC")
			return
		}
		h(w, r)
	}
}

// GET /api/devices
func (s *Server) listDevices(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"devices": s.cfg.Devices, "revoked": s.cfg.Revoked})
}

// POST /api/devices/revoke {"target": id ou nome}
func (s *Server) revokeDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Target string `json:"target"`
	}
	if err := decode(r, &req); err != nil || req.Target == "" {
		writeErr(w, http.StatusBadRequest, "informe o id ou o nome do celular")
		return
	}
	ids := s.revoke(req.Target)
	if len(ids) == 0 {
		writeErr(w, http.StatusNotFound, "nenhum celular com esse id ou nome")
		return
	}
	log.Printf("revogado: %v", ids)
	writeJSON(w, http.StatusOK, map[string]any{"revoked": ids})
}

func withAuth(r *http.Request, a authResult, deviceID string) *http.Request {
	client := deviceID
	if a == authMaster {
		client = "master"
	}
	ctx := context.WithValue(r.Context(), authKey, a)
	return r.WithContext(context.WithValue(ctx, clientKey, client))
}
