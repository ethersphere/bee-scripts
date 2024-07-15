package main

import (
	"flag"
	"log"
	"readSI/postage"
	"readSI/redistribution"
	"readSI/reward"
	"readSI/stake"
	"time"
)

func main() {

	var (
		cmd         string
		since       time.Duration
		sinceRound  int
		countryData bool
		format      string
	)

	flag.StringVar(&cmd, "cmd", "redistribution", "main cmd to run eg: 'redistribution' | 'postage' | 'stake'")
	flag.DurationVar(&since, "since", time.Hour*24*7, "amount of time to rollback")
	flag.IntVar(&sinceRound, "since-round", 0, "amount of rounds to rollback")
	flag.BoolVar(&countryData, "countries", false, "display extra data about countries")
	flag.StringVar(&format, "format", "table", "response format eg: 'json' | 'table' , default 'table'")
	flag.Parse()

	switch cmd {
	case "redistribution":
		redistribution.Run(since, sinceRound, countryData)
	case "postage":
		postage.Run(since, format)
	case "stake":
		stake.Run(since, format)
	case "reward":
		reward.Run(since, format)
	default:
		log.Fatal("unrecognized cmd")
	}
}
