package main

import (
	"encoding/hex"
	"flag"
	"fmt"
	"log"
	"path/filepath"

	"github.com/ethersphere/bee/pkg/crypto"
	filekeystore "github.com/ethersphere/bee/pkg/keystore/file"
)

func main() {

	var (
		dataDir  string
		password string
	)

	flag.StringVar(&dataDir, "data-dir", "", "swarm data directory")
	flag.StringVar(&password, "password", "", "password")
	flag.Parse()

	if dataDir == "" || password == "" {
		log.Fatal("missing args: ex -data-dir or -password")
	}

	keystore := filekeystore.New(filepath.Join(dataDir, "keys"))

	log.Printf("data-dir %s, password %s", dataDir, password)

	swarmPrivateKey, created, err := keystore.Key("swarm", password, crypto.EDGSecp256_K1)
	if err != nil {
		log.Fatal(err)
	}

	private, err := crypto.EDGSecp256_K1.Encode(swarmPrivateKey)
	if err != nil {
		log.Fatal(fmt.Errorf("encode private: %w", err))
	}

	log.Printf("swarm private key %s , created %v", hex.EncodeToString(private), created)
}
