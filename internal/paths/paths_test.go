package paths

import (
	"strings"
	"testing"
)

func TestConfigPathRespectsXDG(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", "/tmp/cfg")
	if got := Config(); got != "/tmp/cfg/horae/recipes.toml" {
		t.Errorf("Config() = %q", got)
	}
}

func TestStatePathRespectsXDG(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "/tmp/st")
	if got := State(); got != "/tmp/st/horae/state.toml" {
		t.Errorf("State() = %q", got)
	}
}

func TestAppContractPathsUnderStateDir(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "/tmp/st")
	cases := map[string]func() string{
		"/tmp/st/horae/current.json":   Current,
		"/tmp/st/horae/last-run.json":  LastRun,
		"/tmp/st/horae/pause.json":     Pause,
		"/tmp/st/horae/overrides.json": Overrides,
		"/tmp/st/horae/horae.lock":     Lock,
	}
	for want, fn := range cases {
		if got := fn(); got != want {
			t.Errorf("got %q, want %q", got, want)
		}
	}
}

func TestLogPathHasDate(t *testing.T) {
	p := Log()
	if !strings.Contains(p, "horae") || !strings.HasSuffix(p, ".log") {
		t.Errorf("Log() = %q", p)
	}
}
