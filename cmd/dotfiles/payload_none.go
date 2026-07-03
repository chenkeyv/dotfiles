//go:build !embedded

package main

import "io/fs"

func embeddedPayloadFS() fs.FS {
	return nil
}
