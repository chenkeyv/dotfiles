//go:build embedded

package main

import (
	"embed"
	"io/fs"
)

//go:embed all:payload
var embeddedFS embed.FS

func embeddedPayloadFS() fs.FS {
	sub, err := fs.Sub(embeddedFS, embeddedPayloadDir)
	if err != nil {
		return nil
	}
	return sub
}
