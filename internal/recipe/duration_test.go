package recipe

import (
	"testing"
	"time"
)

func TestParseDuration(t *testing.T) {
	cases := []struct {
		in   string
		want time.Duration
	}{
		{"30m", 30 * time.Minute},
		{"6h", 6 * time.Hour},
		{"1d", 24 * time.Hour},
		{"7d", 7 * 24 * time.Hour},
		{"1w", 7 * 24 * time.Hour},
		{"1d12h", 36 * time.Hour},
		{"1.5d", 36 * time.Hour},
	}
	for _, c := range cases {
		got, err := ParseDuration(c.in)
		if err != nil {
			t.Fatalf("ParseDuration(%q) error: %v", c.in, err)
		}
		if got != c.want {
			t.Errorf("ParseDuration(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestParseDurationErrors(t *testing.T) {
	for _, in := range []string{"", "abc", "10x", "  "} {
		if _, err := ParseDuration(in); err == nil {
			t.Errorf("ParseDuration(%q) expected error, got nil", in)
		}
	}
}

func TestDurationUnmarshalText(t *testing.T) {
	var d Duration
	if err := d.UnmarshalText([]byte("6h")); err != nil {
		t.Fatal(err)
	}
	if d.Std() != 6*time.Hour {
		t.Errorf("got %v, want 6h", d.Std())
	}
}
