package response

import (
	"encoding/json"
	"log"
)

type ResponseList struct {
	List interface{}
}

type Printer interface {
	PrintJsonResponse()
	PrintTableResponse()
}

func PrintResponse(p Printer, format string) {
	switch format {
	case "json":
		p.PrintJsonResponse()
	case "table":
		p.PrintTableResponse()
	default:
		log.Printf("Unknown format: %s", format)
	}
}

func (rl *ResponseList) PrintJsonResponse() {
	jl, err := json.MarshalIndent(rl.List, "", "  ")
	if err != nil {
		log.Printf("Error marshalling to JSON: %v", err)
		return
	}
	log.Println(string(jl))
}
