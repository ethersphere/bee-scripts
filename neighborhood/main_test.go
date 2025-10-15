package main

import (
	"testing"

	"github.com/ethersphere/bee/pkg/swarm"
)

func TestXXX(t *testing.T) {

	prox := 9

	a1 := swarm.MustParseHexAddress("5c32a2fe3d217af8c943fa665ebcfbdf7ab9af0cf1b2a1c8e5fc163dad2f5c7b")
	a2 := swarm.MustParseHexAddress("eac0903e59ff1c1a5f1d7d218b33f819b199aa0f68a19fd5fa02b7f84982b55d")
	a3 := swarm.MustParseHexAddress("70143dd2863ae07edfe7c1bfee75daea06226f0678e1117337d274492226bfe0")

	a1Prefix := swarm.MustParseHexAddress("5c00000000000000000000000000000000000000000000000000000000000000")
	a2Prefix := swarm.MustParseHexAddress("ea80000000000000000000000000000000000000000000000000000000000000")
	a3Prefix := swarm.MustParseHexAddress("7000000000000000000000000000000000000000000000000000000000000000")

	a1BitStr := "010111000"
	a2BitStr := "111010101"
	a3BitStr := "011100000"

	if !firstNBits(a1.Bytes(), prox).Equal(a1Prefix) {
		t.Fatal("mismatch")
	}
	if !firstNBits(a2.Bytes(), prox).Equal(a2Prefix) {
		t.Fatal("mismatch")
	}
	if !firstNBits(a3.Bytes(), prox).Equal(a3Prefix) {
		t.Fatal("mismatch")
	}

	if bitStr(a1.Bytes(), prox) != a1BitStr {
		t.Fatal("mismatch")
	}
	if bitStr(a2.Bytes(), prox) != a2BitStr {
		t.Fatal("mismatch")
	}
	if bitStr(a3.Bytes(), prox) != a3BitStr {
		t.Fatal("mismatch")
	}
}
