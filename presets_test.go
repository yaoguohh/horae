package main

import (
	"context"
	"encoding/json"
	"horae/internal/recipe"
	"horae/internal/runner"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestHermesPresetRunsStableDailyWithMinimalPATH(t *testing.T) {
	data, err := os.ReadFile("app/presets.json")
	if err != nil {
		t.Fatal(err)
	}
	var presets []struct {
		ID      string `json:"id"`
		Cadence string `json:"cadence"`
		Shell   string `json:"shell"`
	}
	if err := json.Unmarshal(data, &presets); err != nil {
		t.Fatal(err)
	}
	var hermes []recipe.Step
	for _, preset := range presets {
		if preset.ID == "hermes" {
			cadence, err := recipe.ParseDuration(preset.Cadence)
			if err != nil {
				t.Fatal(err)
			}
			hermes = append(hermes, recipe.Step{ID: preset.ID, Cadence: recipe.Duration(cadence), Shell: preset.Shell})
		}
	}
	if len(hermes) != 1 {
		t.Fatalf("expected exactly one Hermes preset, got %d", len(hermes))
	}
	if got := hermes[0].Cadence.Std(); got != 24*time.Hour {
		t.Fatalf("expected daily cadence, got %s", got)
	}

	home := t.TempDir()
	bin := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(bin, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "hermes"), []byte("#!/bin/sh\nprintf '%s\\n' \"$@\"\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("SHELL", "/bin/sh")
	result := (runner.ExecRunner{}).Run(context.Background(), hermes[0], 5*time.Second, "/usr/bin:/bin")
	if result.Outcome != runner.OutcomeSuccess || result.Stdout != "update\n--yes\n--channel\nstable\n" {
		t.Fatalf("unexpected Hermes invocation: %+v", result)
	}
}
