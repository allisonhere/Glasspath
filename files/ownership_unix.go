//go:build unix

package files

import (
	"os"
	"os/user"
	"strconv"
	"syscall"
)

func ownershipFromInfo(info os.FileInfo) (uid int, gid int, owner string, group string) {
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return
	}

	uid = int(stat.Uid)
	gid = int(stat.Gid)

	if u, err := user.LookupId(strconv.Itoa(uid)); err == nil {
		owner = u.Username
	}

	if g, err := user.LookupGroupId(strconv.Itoa(gid)); err == nil {
		group = g.Name
	}

	return
}
