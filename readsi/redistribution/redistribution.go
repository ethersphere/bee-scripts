package redistribution

import (
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"readSI/util"
	"sort"
	"strings"
	"time"

	"github.com/fatih/color"
)

func Run(untilTime time.Duration, untilRound int, countryData bool) {

	var (
		next = 0
		eng  = engine{rounds: map[int]*roundState{}}
		api  = "https://api.swarmscan.io/v1/redistribution/rounds"
	)

	untilT := time.Now().Add(-untilTime)

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

			if r.RoundNumber < untilRound {
				break loop
			}

			if len(r.Events) > 0 && r.Events[0].BlockTime.Before(untilT) {
				break loop
			}

			for _, e := range r.Events {
				eng.process(r.RoundNumber, e)
			}
		}
	}

	redisStat, profitStat := eng.done(countryData)

	fmt.Printf("%-30s%v\n", "total rounds:", redisStat.rounds)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%v\n", "frozen rounds:", redisStat.frozenRounds)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%0.2f%%\n", "frozen rounds:", 100*(float64(redisStat.frozenRounds)/float64(redisStat.rounds)))
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%v\n", "minority wins:", redisStat.minorityWins)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%v\n", "minority win freezes :", redisStat.minorityWinsFreezes)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%v\n", "total players:", redisStat.totalPlayers)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%0.2f\n", "avg players per round:", float64(redisStat.totalPlayers)/float64(redisStat.rounds))
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%v\n", "total freezes:", redisStat.totalFreezes)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%v\n", "unreachable frozen nodes:", redisStat.frozenUnReachable)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%v\n", "frozen countries:", redisStat.frozenCountries)
	fmt.Printf("%s\n", strings.Repeat("-", 45))

	// rewards
	fmt.Printf("%-30s%.2f\n", "total reward:", profitStat.totalReward)
	fmt.Printf("%s\n", strings.Repeat("-", 45))
	fmt.Printf("%-30s%.2f\n", "avg reward:", profitStat.totalReward/float64(profitStat.rounds))
	fmt.Printf("%s\n", strings.Repeat("-", 45))
}

type rounds struct {
	Rounds []round
	Next   int
}

type round struct {
	RoundNumber int
	Events      []event
}

type event struct {
	EventType string `json:"type"`
	Name      string `json:"name"`
	BlockTime time.Time
	ClaimTransaction
	RevealTransaction
}

type ClaimTransaction struct {
	Winner       winner
	StakeFrozen  []frozen
	RewardAmount *big.Int
}

type winner struct {
	Overlay string
	Hash    string
	Depth   int
}

type frozen struct {
	Overlay string
}

type RevealTransaction struct {
	Data revealData
}

type revealData struct {
	Overlay           string
	ReserveCommitment string
	Depth             int
}

type roundState struct {
	reveals []revealData
	claim   ClaimTransaction
}

const (
	Unknown int = iota
	Reveal
	Claim
)

type engine struct {
	rounds map[int]*roundState
}

type redisStats struct {
	rounds              int
	frozenRounds        int
	totalFreezes        int
	totalPlayers        int
	minorityWins        int
	minorityWinsFreezes int

	frozenUnReachable int
	frozenCountries   map[string]int
}

type profitStats struct {
	rounds      int
	totalReward float64
}

func (eng *engine) process(round int, e event) {

	if eng.rounds[round] == nil {
		eng.rounds[round] = &roundState{}
	}

	if e.Name == "revealed" {
		eng.rounds[round].reveals = append(eng.rounds[round].reveals, e.Data)
	}

	if e.EventType == "claim transaction" {
		eng.rounds[round].claim = e.ClaimTransaction
	}
}

func (eng *engine) done(countryData bool) (redisStats, profitStats) {

	keys := make([]int, 0, len(eng.rounds))
	for k := range eng.rounds {
		keys = append(keys, k)
	}
	sort.Ints(keys)

	redisStats := redisStats{frozenCountries: map[string]int{}}
	pStats := profitStats{}

	for _, n := range keys {
		r := eng.rounds[n]

		redisStats.rounds++
		pStats.rounds++

		if r.claim.Winner.Overlay == "" {
			color.Red("ROUND %d WAS NOT CLAIMED\n", n)
			continue
		}

		pStats.totalReward += util.ToBZZ(big.NewFloat(0).SetInt(r.claim.RewardAmount))

		redisStats.totalPlayers += len(r.reveals)

		minoriyWin, mismatches, gstr := groupStr(r.claim.Winner.Hash, r.reveals)
		if minoriyWin {
			redisStats.minorityWins++
			redisStats.minorityWinsFreezes += mismatches
		}

		fmt.Printf("round\t%d\nreveals\t%s\n", n, gstr)
		fmt.Printf("reward\t%.2f BZZ\n", util.ToBZZ(big.NewFloat(0).SetInt(r.claim.RewardAmount)))
		color.Green("winner\t%s depth\t%d\n", util.Trim(r.claim.Winner.Overlay), depth(r.claim.Winner.Overlay, r.reveals))

		redisStats.totalFreezes += len(r.claim.StakeFrozen)

		if len(r.claim.StakeFrozen) > 0 {
			redisStats.frozenRounds++
		}

		for _, f := range r.claim.StakeFrozen {
			color.Red("loser\t%s depth\t%d\n", util.Trim(f.Overlay), depth(f.Overlay, r.reveals))

			if !countryData {
				continue
			}

			unreachable, country, err := util.GetStatus(f.Overlay)
			if err != nil {
				continue
			}
			if unreachable {
				redisStats.frozenUnReachable++
			}
			redisStats.frozenCountries[country]++
		}

		fmt.Println("")
	}

	return redisStats, pStats
}

func depth(overlay string, reveals []revealData) int {

	for _, r := range reveals {
		if r.Overlay == overlay {
			return r.Depth
		}
	}

	return 0
}

func groupStr(winnerHash string, reveals []revealData) (bool, int, string) {

	group := map[string]int{}

	for _, r := range reveals {
		group[r.ReserveCommitment]++
	}

	str := fmt.Sprintf("%d", group[winnerHash])

	mismatches := 0

	for hash, c := range group {
		if hash != winnerHash {
			str += fmt.Sprintf("-%d", c)
			mismatches += c
		}
	}

	return mismatches > group[winnerHash], mismatches, str
}
