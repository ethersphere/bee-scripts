package stake

import (
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"readSI/response"
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

type StakeResponse struct {
	Owner   common.Address `json:"owner"`
	Amount  float64        `json:"amount"`
	Country string         `json:"country"`
	Block   uint64         `json:"block"`
	Time    time.Time      `json:"time"`
}

type StakeResponeList struct {
	response.ResponseList
}

func Run(until time.Duration, format string) {

	var (
		next = ""
		api  = "https://api.swarmscan.io/v1/events/staking/stake-updated"
	)

	untilT := time.Now().Add(-until)

	lsr := []StakeResponse{}

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
			lsr = append(lsr, StakeResponse{e.Data.Owner, util.ToBZZ(big.NewFloat(0).SetInt(e.Data.StakeAmount)), country, e.BlockNumber, e.BlockTime})
		}
	}

	listResponse := StakeResponeList{ResponseList: response.ResponseList{List: lsr}}
	response.PrintResponse(&listResponse, format)
}

func (lr *StakeResponeList) PrintTableResponse() {
	headerFmt := color.New(color.FgGreen, color.Underline).SprintfFunc()
	columnFmt := color.New(color.FgYellow).SprintfFunc()
	tbl := table.New("Owner", "Amount (BZZ)", "Country", "Block", "Time")
	tbl.WithHeaderFormatter(headerFmt).WithFirstColumnFormatter(columnFmt)

	for _, response := range lr.ResponseList.List.([]StakeResponse) {
		tbl.AddRow(response.Owner, response.Amount, response.Country, response.Block, response.Time)
	}

	tbl.Print()
}
