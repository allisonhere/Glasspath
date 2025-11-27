//go:build !unix

package files

import "os"

func ownershipFromInfo(info os.FileInfo) (uid int, gid int, owner string, group string) {
	return
}
