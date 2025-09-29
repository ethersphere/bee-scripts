while IFS= read -r tx; do
     printf "Deleting: %s\n" ${tx}
     curl -XDELETE -H "Gas-Price: 1000000000000" $1/transactions/${tx}
done <<< "$(curl $1/transactions | jq '.pendingTransactions | .[] | .transactionHash' | tr -d '"')"