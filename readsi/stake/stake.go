package stake

import (
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"readSI/util"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/fatih/color"
	"github.com/rodaine/table"
)

type postageEvents struct {
	Events []postageEvent
	Next   string
}

type postageEvent struct {
	Data        postageCreate
	BlockNumber uint64
	BlockTime   time.Time
}

type postageCreate struct {
	StakeAmount *big.Int
	Owner       common.Address
	Overlay     string
}

func Run(until time.Duration) {

	var (
		next = ""
		api  = "https://api.swarmscan.io/v1/events/staking/stake-updated"
	)

	untilT := time.Now().Add(-until)

	headerFmt := color.New(color.FgGreen, color.Underline).SprintfFunc()
	columnFmt := color.New(color.FgYellow).SprintfFunc()
	tbl := table.New("Owner", "Amount (BZZ)", "Country", "Block", "Time")
	tbl.WithHeaderFormatter(headerFmt).WithFirstColumnFormatter(columnFmt)

loop:
	for {

		url := api
		if next != "" {
			url = fmt.Sprintf("%s?start=%s", api, next)
		}

		data, err := http.Get(url)
		if err != nil {
			log.Fatal(err)
		}

		var events postageEvents
		err = json.NewDecoder(data.Body).Decode(&events)
		if err != nil {
			log.Fatal(err)
		}

		next = events.Next

		for _, e := range events.Events {
			if e.BlockTime.Before(untilT) {
				break loop
			}

			_, country, _ := util.GetStatus(e.Data.Overlay)
			tbl.AddRow(e.Data.Owner, util.ToBZZ(big.NewFloat(0).SetInt(e.Data.StakeAmount)), country, e.BlockNumber, e.BlockTime)
		}
	}

	tbl.Print()
}
