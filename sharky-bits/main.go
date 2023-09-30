package main

import (
	"fmt"
	"log"
	"os"
)

func main() {

	filename := os.Args[1:][0]

	data, err := os.ReadFile(filename)
	if err != nil {
		log.Fatal(err)
	}

	oneBits := 0

	for _, b := range data {
		for b != 0 {
			oneBits += int(b & 0x1)
			b >>= 1
		}
	}

	fmt.Println("bits length", len(data)*8, "one bits", oneBits)
}
