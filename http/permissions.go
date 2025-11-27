package http

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/spf13/afero"

	"github.com/filebrowser/filebrowser/v2/files"
)

type permissionsRequest struct {
	Mode      string `json:"mode"`
	Owner     string `json:"owner"`
	Group     string `json:"group"`
	Recursive bool   `json:"recursive"`
}

type permissionOptions struct {
	mode         *os.FileMode
	uid          int
	gid          int
	applyOwner   bool
	applyGroup   bool
	recursive    bool
	skipSymlinks bool
}

var permissionsPatchHandler = withUser(func(_ http.ResponseWriter, r *http.Request, d *data) (int, error) {
	if !d.user.Perm.Modify || !d.Check(r.URL.Path) {
		return http.StatusForbidden, nil
	}

	var req permissionsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		return http.StatusBadRequest, err
	}

	if strings.TrimSpace(req.Mode) == "" && strings.TrimSpace(req.Owner) == "" && strings.TrimSpace(req.Group) == "" {
		return http.StatusBadRequest, fmt.Errorf("no permission changes requested")
	}

	file, err := files.NewFileInfo(&files.FileOptions{
		Fs:         d.user.Fs,
		Path:       r.URL.Path,
		Modify:     d.user.Perm.Modify,
		Expand:     false,
		ReadHeader: d.server.TypeDetectionByHeader,
		Checker:    d,
	})
	if err != nil {
		return errToStatus(err), err
	}

	if file.IsSymlink {
		return http.StatusBadRequest, fmt.Errorf("refusing to change permissions on a symlink")
	}

	opts, err := buildPermissionOptions(req)
	if err != nil {
		return http.StatusBadRequest, err
	}

	opts.recursive = req.Recursive
	opts.skipSymlinks = true

	resolvePath := func(p string) string {
		if base, ok := d.user.Fs.(*afero.BasePathFs); ok {
			return afero.FullBaseFsPath(base, p)
		}
		return p
	}

	err = d.RunHook(func() error {
		return applyPermissions(d.user.Fs, resolvePath, file.Path, opts)
	}, "chmod", r.URL.Path, "", d.user)

	status := errToStatus(err)
	if err == nil {
		status = http.StatusNoContent
	}

	return status, err
})

func buildPermissionOptions(req permissionsRequest) (permissionOptions, error) {
	opts := permissionOptions{
		uid:          -1,
		gid:          -1,
		skipSymlinks: true,
	}

	if strings.TrimSpace(req.Mode) != "" {
		parsed, err := strconv.ParseUint(req.Mode, 8, 32)
		if err != nil {
			return opts, fmt.Errorf("invalid mode %q (expect octal, e.g. 755)", req.Mode)
		}
		mode := os.FileMode(parsed & 0o777)
		opts.mode = &mode
	}

	if strings.TrimSpace(req.Owner) != "" {
		uid, err := parseUserOrID(req.Owner)
		if err != nil {
			return opts, fmt.Errorf("invalid owner %q: %w", req.Owner, err)
		}
		opts.uid = uid
		opts.applyOwner = true
	}

	if strings.TrimSpace(req.Group) != "" {
		gid, err := parseGroupOrID(req.Group)
		if err != nil {
			return opts, fmt.Errorf("invalid group %q: %w", req.Group, err)
		}
		opts.gid = gid
		opts.applyGroup = true
	}

	return opts, nil
}

func parseUserOrID(raw string) (int, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return -1, nil
	}
	if uid, err := strconv.Atoi(raw); err == nil {
		return uid, nil
	}
	u, err := user.Lookup(raw)
	if err != nil {
		return -1, err
	}
	uid, err := strconv.Atoi(u.Uid)
	if err != nil {
		return -1, err
	}
	return uid, nil
}

func parseGroupOrID(raw string) (int, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return -1, nil
	}
	if gid, err := strconv.Atoi(raw); err == nil {
		return gid, nil
	}
	g, err := user.LookupGroup(raw)
	if err != nil {
		return -1, err
	}
	gid, err := strconv.Atoi(g.Gid)
	if err != nil {
		return -1, err
	}
	return gid, nil
}

func applyPermissions(fs afero.Fs, fullPath func(path string) string, root string, opts permissionOptions) error {
	return afero.Walk(fs, root, func(currentPath string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if currentPath != root && !opts.recursive {
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		if opts.skipSymlinks && files.IsSymlink(info.Mode()) {
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		if opts.mode != nil {
			if err := fs.Chmod(currentPath, *opts.mode); err != nil {
				return err
			}
		}

		if opts.applyOwner || opts.applyGroup {
			uid := opts.uid
			gid := opts.gid
			if !opts.applyOwner {
				uid = -1
			}
			if !opts.applyGroup {
				gid = -1
			}
			if err := os.Chown(fullPath(currentPath), uid, gid); err != nil {
				return err
			}
		}

		return nil
	})
}
