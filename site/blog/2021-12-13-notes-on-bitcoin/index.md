---
slug: notes-on-bitcoin
title: Notes on Bitcoin
date: 2021-12-13
authors: taylor
tags: [bitcoin]
---

I have never gotten a satisfactory answer to the question "what is Bitcoin" so thought I'd give it a shot given my new understanding of Bitcoin. Perhaps I can save someone some time.

## What is Bitcoin?

### Computer Science Fundamentals

Send money (cryptocurrency) without a central authority. The power to send the money resides in the keys of each wallet.

There are 3 fundamental principles to understand cryptocurrency: asymmetric encryption (public/private keys), hash algorithms, and blockchain.

![Bitcoin](./12-13-21.jpg)

{/* truncate */}

**Encryption** allows you to protect data, by changing it in a predictable way, reversible only with a key. Asymmetric encryption involves 2 keys — one is used to protect the data, but cannot be used to reveal it. Only the second key can reveal the protected data. Private/public keys are essentially what make up a wallet.

**A hash algorithm** is a function that returns a fixed length output, for example 256 bits, when given input, for example a list of transactions. You will always get the same hash output with the same input. A viable cryptocurrency hash algorithm unpredictably changes the output with any change to the input.

**Blockchain** is a list of linked blocks of data. Each block references the previous block, and includes a hash of that block. This means blocks cannot be modified without invalidating the hashes for the remainder of the chain.

### Putting it together

In order to ensure money cannot be spent twice, consensus must be found among the network. Otherwise there is nothing stopping me from sending money to you, and to myself (double spend). I could dispute that the first transaction was invalid. Which one is valid and which is not? This is a simple example of a fork. With a blockchain, we can ensure only one transaction is valid by reaching consensus. In Bitcoin that consensus is simply reached by accepting the longest chain of blocks. This is why waiting for 3 blocks makes it reasonably certain that the transaction is final.

Blocks are made up of a group of signed transactions, each signed using the private key for the wallet, and the hash of the previous block. In order for a new block to be considered valid in the chain, the hash of the new block must be within a target range, for example a hash with 16 preceding 0s. The odds of computing a hash that starts with 16 preceding 0s is very low. Bitcoin automatically changes the target range in order to reach an average of ten minutes between blocks. Small modifications can be made to the block in order to change the hash: a nonce, the date/time, changing the group of transactions in the block.

Whoever submits a valid block to the network first is rewarded for "mining" with a baked-in reward which halves every so often, about a year, and collects all of the fees submitted from all of the transactions included in the new block.

When users want to send Bitcoin, they submit a transaction to the network, which is then gossiped about to other nodes. A part of the transaction may include a transaction fee. Higher fees mean higher priority for the miners, so with higher congestion come higher fees. It's possible to submit a transaction with no fee, but it may take a long time to ever be added to the blockchain because miners are not incentivized to include the transaction.

That concludes my explanation of "What is Bitcoin?"

### Extra

Another interesting thing to learn about is the UTXO concept that Bitcoin uses. Rather than have an account balance that is modified over time, and requires all of history to determine the current state, Bitcoin validates new transactions simply by looking at unspent transaction output — money that has been sent to you, that you haven't sent anywhere else.

### Web3

I've spent the last 2 months trying to catch up to the Web3 world, but I still feel far behind. The thing I'm most excited to try next is building my own blockchain using Substrate (the open source blockchain building project, which constitutes ~80% of the Polkadot blockchain). Substrate allows you to focus on the State Transition Function in the Runtime, rather than all of the other complicated parts of building a blockchain.

Here's to hoping, and working towards the free web!

[Discuss on Reddit](https://www.reddit.com/r/ExistentialCompany/comments/rfzl4s/notes_on_bitcoin)
