package main

import (
    "fmt"
    "os"

    "golang.org/x/mod/sumdb/dirhash"
)

func main() {
    if len(os.Args) != 2 {
        fmt.Fprintf(os.Stderr, "Usage: %s <zip-file>\n", os.Args[0])
        os.Exit(1)
    }

    zipPath := os.Args[1]
    hash, err := dirhash.HashZip(zipPath, dirhash.DefaultHash)
    if err != nil {
        fmt.Fprintf(os.Stderr, "Error: %v\n", err)
        os.Exit(1)
    }

    fmt.Println(hash)
}
