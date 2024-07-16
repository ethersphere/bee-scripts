package reward

import (
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"readSI/response"
	"readSI/util"
	"time"

	"github.com/fatih/color"
	"github.com/rodaine/table"
)

type rounds struct {
	Rounds []round
	Next   int
}

type round struct {
	RoundNumber int
	Events      []event
}

type event struct {
	EventType   string `json:"type"`
	Name        string
	BlockNumber uint64
	BlockTime   time.Time
	ClaimTransaction
}

type ClaimTransaction struct {
	Winner       winner
	RewardAmount *big.Int
}

type winner struct {
	Overlay string
	Owner   string
	Hash    string
	Depth   int
}

type RewardResponse struct {
	Reward  float64
	Overlay string
	Owner   string
	Country string
	Block   uint64
	Time    time.Time
}

type RewardResponeList struct {
	response.ResponseList
}

func Run(until time.Duration, format string) {

	var (
		next = 0
		api  = "https://api.swarmscan.io/v1/redistribution/rounds"
	)

	untilT := time.Now().Add(-until)

	lrr := []RewardResponse{}

loop:
	for {

		url := api
		if next != 0 {
			url = fmt.Sprintf("%s?start=%d", api, next)
		}

		data, err := http.Get(url)
		if err != nil {
			log.Fatal(err)
		}

		var r rounds
		err = json.NewDecoder(data.Body).Decode(&r)
		if err != nil {
			log.Fatal(err)
		}

		next = r.Next

		for _, r := range r.Rounds {
			for _, e := range r.Events {
				if e.BlockTime.Before(untilT) {
					break loop
				}
				if e.EventType == "claim transaction" {
					_, country, _ := util.GetStatus(e.Winner.Overlay)

					lrr = append(lrr, RewardResponse{util.ToBZZ(big.NewFloat(0).SetInt(e.RewardAmount)), util.Trim(e.Winner.Overlay), e.Winner.Owner, country, e.BlockNumber, e.BlockTime})
				}
			}
		}
	}

	listResponse := RewardResponeList{ResponseList: response.ResponseList{List: lrr}}
	response.PrintResponse(&listResponse, format)

}

func (lr *RewardResponeList) PrintTableResponse() {
	headerFmt := color.New(color.FgGreen, color.Underline).SprintfFunc()
	columnFmt := color.New(color.FgYellow).SprintfFunc()
	tbl := table.New("Reward (BZZ)", "Overlay", "Owner", "Country", "Block", "Time")
	tbl.WithHeaderFormatter(headerFmt).WithFirstColumnFormatter(columnFmt)

	for _, response := range lr.ResponseList.List.([]RewardResponse) {
		tbl.AddRow(response.Reward, response.Overlay, response.Owner, response.Country, response.Block, response.Time)
	}

	tbl.Print()
}
