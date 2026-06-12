// Package report 持有引擎写、菜单栏 app 读的输出(实时进度 / 最近结果 / status 视图)。
// 全部 JSON，原子写(temp + rename)避免 app 读到半截；权限 0600 目录 0700。
package report

import (
	"encoding/json"
	"os"
	"path/filepath"
)

func writeJSON(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
