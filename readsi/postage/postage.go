package postage

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
	TotalAmount       *big.Int
	NormalisedBalance *big.Int
	Depth             int
	Owner             common.Address
}

type PostageResponse struct {
	Overlay           string    `json:"overlay"`
	Depth             int       `json:"depth"`
	TotalAmount       float64   `json:"totalamount"`
	NormalisedBalance uint64    `json:"normalisedbalance"`
	Country           string    `json:"country"`
	Block             uint64    `json:"block"`
	Time              time.Time `json:"time"`
}

type PostageResponeList struct {
	response.ResponseList
}

func Run(until time.Duration, format string) {

	var (
		next = ""
		api  = "https://api.swarmscan.io/v1/events/postage-stamp/batch-created"
	)

	untilT := time.Now().Add(-until)
	lpr := []PostageResponse{}

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
			status, _ := util.GetStatusEth(e.Data.Owner.String())
			lpr = append(lpr, PostageResponse{status.Overlay, e.Data.Depth, util.ToBZZ(big.NewFloat(0).SetInt(e.Data.TotalAmount)), e.Data.NormalisedBalance.Uint64(), status.Location.Country, e.BlockNumber, e.BlockTime})
		}
	}
	listResponse := PostageResponeList{ResponseList: response.ResponseList{List: lpr}}
	response.PrintResponse(&listResponse, format)
}

func (lr *PostageResponeList) PrintTableResponse() {
	headerFmt := color.New(color.FgGreen, color.Underline).SprintfFunc()
	columnFmt := color.New(color.FgYellow).SprintfFunc()
	tbl := table.New("Overlay", "Depth", "Total Amount (BZZ)", "Normalized Balance", "Country", "Block", "Time")
	tbl.WithHeaderFormatter(headerFmt).WithFirstColumnFormatter(columnFmt)

	for _, response := range lr.ResponseList.List.([]PostageResponse) {
		tbl.AddRow(response.Overlay, response.Depth, response.TotalAmount, response.NormalisedBalance, response.Country, response.Block, response.Time)
	}

	tbl.Print()
}
