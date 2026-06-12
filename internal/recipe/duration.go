package recipe

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Duration 包装 time.Duration，支持 TOML 文本反序列化（含 d/w 单位）。
type Duration time.Duration

func (d Duration) Std() time.Duration { return time.Duration(d) }

func (d *Duration) UnmarshalText(text []byte) error {
	parsed, err := ParseDuration(string(text))
	if err != nil {
		return err
	}
	*d = Duration(parsed)
	return nil
}

var dwRe = regexp.MustCompile(`([0-9]*\.?[0-9]+)([dw])`)

// ParseDuration 在 time.ParseDuration（支持 s/m/h）之上扩展 d（天）/w（周）。
// 先把 <n>d / <n>w 展开成等价小时数，再交给标准库累加。
func ParseDuration(s string) (time.Duration, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, fmt.Errorf("empty duration")
	}
	expanded := dwRe.ReplaceAllStringFunc(s, func(m string) string {
		sub := dwRe.FindStringSubmatch(m)
		n, _ := strconv.ParseFloat(sub[1], 64)
		hours := n * 24
		if sub[2] == "w" {
			hours = n * 24 * 7
		}
		return strconv.FormatFloat(hours, 'f', -1, 64) + "h"
	})
	dur, err := time.ParseDuration(expanded)
	if err != nil {
		return 0, fmt.Errorf("invalid duration %q: %w", s, err)
	}
	return dur, nil
}
