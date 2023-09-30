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
		cmd   string
		since time.Duration
	)

	flag.StringVar(&cmd, "cmd", "redistribution", "main cmd to run eg: 'redistribution' | 'postage' | 'stake'")
	flag.DurationVar(&since, "since", time.Hour*24*7, "amount of time to rollback")
	flag.Parse()

	switch cmd {
	case "redistribution":
		redistribution.Run(since)
	case "postage":
		postage.Run(since)
	case "stake":
		stake.Run(since)
	case "reward":
		reward.Run(since)
	default:
		log.Fatal("unrecognized cmd")
	}
}
