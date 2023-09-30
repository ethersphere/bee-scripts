package util

import (
	"encoding/json"
	"math/big"
	"net/http"
	"strings"
)

func ToBZZ(p *big.Float) float64 {
	f, _ := big.NewFloat(0).Quo(p, big.NewFloat(10000000000000000)).Float64()
	return f
}

func Trim(s string) string {
	return strings.TrimPrefix(s, "0x")
}

type location struct {
	Country string
}

type nodeStatus struct {
	Overlay     string
	Unreachable bool
	Location    location
}

var cache map[string]nodeStatus

func init() {
	cache = map[string]nodeStatus{}
}

func GetStatus(overlay string) (bool, string, error) {

	overlay = Trim(overlay)

	if status, ok := cache[overlay]; ok {
		return status.Unreachable, status.Location.Country, nil
	}

	data, err := http.Get("https://api.swarmscan.io/v1/network/nodes/" + overlay)
	if err != nil {
		return false, "", err
	}

	var status nodeStatus
	err = json.NewDecoder(data.Body).Decode(&status)
	if err != nil {
		return false, "", err
	}

	cache[overlay] = status

	return status.Unreachable, status.Location.Country, nil
}

func GetStatusEth(eth string) (nodeStatus, error) {

	if status, ok := cache[eth]; ok {
		return status, nil
	}

	data, err := http.Get("https://api.swarmscan.io/v1/network/nodes/ethereum/" + eth)
	if err != nil {
		return nodeStatus{}, err
	}

	var status nodeStatus
	err = json.NewDecoder(data.Body).Decode(&status)
	if err != nil {
		return nodeStatus{}, err
	}

	cache[eth] = status

	return status, nil
}
