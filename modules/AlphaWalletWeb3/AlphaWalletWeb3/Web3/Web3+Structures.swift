//
//  Web3+Structures.swift
//  Alamofire
//
//  Created by Alexander Vlasov on 26.12.2017.
//

import Foundation
import BigInt

fileprivate func decodeHexToData<T>(_ container: KeyedDecodingContainer<T>, key: KeyedDecodingContainer<T>.Key, allowOptional: Bool = false) throws -> Data? {
    if allowOptional {
        let string = try? container.decode(String.self, forKey: key)
        if string != nil {
            guard let data = Data.fromHex(string!) else { throw DecodeError.initFailure }
            return data
        }
        return nil
    } else {
        let string = try container.decode(String.self, forKey: key)
        guard let data = Data.fromHex(string) else { throw DecodeError.initFailure }
        return data
    }
}

fileprivate func decodeHexToBigUInt<T>(_ container: KeyedDecodingContainer<T>, key: KeyedDecodingContainer<T>.Key, allowOptional: Bool = false) throws -> BigUInt? {
    if allowOptional {
        if let string = try? container.decode(String.self, forKey: key) {
            guard let number = BigUInt(string.stripHexPrefix(), radix: 16) else { throw DecodeError.typeMismatch }
            return number
        }
        return nil
    } else {
        guard let number = BigUInt(try container.decode(String.self, forKey: key).stripHexPrefix(), radix: 16) else { throw DecodeError.typeMismatch }
        return number
    }
}

extension Web3Options: Decodable {
    enum CodingKeys: String, CodingKey {
        case from
        case to
        case gasPrice
        case gas
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.gasLimit = try decodeHexToBigUInt(container, key: .gas)
        self.gasPrice = try decodeHexToBigUInt(container, key: .gasPrice)

        let toString = try container.decode(String.self, forKey: .to)
        var to: EthereumAddress?
        if toString == "0x" || toString == "0x0" {
            to = EthereumAddress.contractDeploymentAddress()
        } else {
            guard let ethAddr = EthereumAddress(toString) else { throw DecodeError.typeMismatch }
            to = ethAddr
        }
        self.to = to
        self.from = try container.decodeIfPresent(EthereumAddress.self, forKey: .to)
        self.value = try decodeHexToBigUInt(container, key: .value)
    }
}

extension Transaction: Decodable {
    enum CodingKeys: String, CodingKey {
        case to
        case data
        case input
        case nonce
        case v
        case r
        case s
        case value
    }

    init(from decoder: Decoder) throws {
        let options = try Web3Options(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)

        var data = try decodeHexToData(container, key: .data, allowOptional: true)
        if data != nil {
            self.data = data!
        } else {
            data = try decodeHexToData(container, key: .input, allowOptional: true)
            if data != nil {
                self.data = data!
            } else {
                throw DecodeError.initFailure
            }
        }

        guard let nonce = try decodeHexToBigUInt(container, key: .nonce) else { throw DecodeError.initFailure }
        self.nonce = nonce

        guard let v = try decodeHexToBigUInt(container, key: .v) else { throw DecodeError.initFailure }
        self.v = v

        guard let r = try decodeHexToBigUInt(container, key: .r) else { throw DecodeError.initFailure }
        self.r = r

        guard let s = try decodeHexToBigUInt(container, key: .s) else { throw DecodeError.initFailure }
        self.s = s

        if options.value == nil || options.to == nil || options.gasLimit == nil || options.gasPrice == nil {
            throw DecodeError.initFailure
        }
        self.value = options.value!
        self.to = options.to!
        self.gasPrice = options.gasPrice!
        self.gasLimit = options.gasLimit!

        let inferedChainID = self.inferedChainID
        if self.inferedChainID != nil && self.v >= BigUInt(37) {
            self.chainID = inferedChainID
        }
    }
}

public struct TransactionDetails: Decodable {
    var blockHash: Data?
    var blockNumber: BigUInt?
    var transactionIndex: BigUInt?
    var transaction: Transaction

    enum CodingKeys: String, CodingKey {
        case blockHash
        case blockNumber
        case transactionIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let blockNumber = try decodeHexToBigUInt(container, key: .blockNumber, allowOptional: true)
        self.blockNumber = blockNumber

        let blockHash = try decodeHexToData(container, key: .blockHash, allowOptional: true)
        self.blockHash = blockHash

        let transactionIndex = try decodeHexToBigUInt(container, key: .blockNumber, allowOptional: true)
        self.transactionIndex = transactionIndex

        let transaction = try Transaction(from: decoder)
        self.transaction = transaction
    }

    init? (_ json: [String: AnyObject]) {
        let bh = json["blockHash"] as? String
        if bh != nil {
            guard let blockHash = Data.fromHex(bh!) else { return nil }
            self.blockHash = blockHash
        }
        let bn = json["blockNumber"] as? String
        let ti = json["transactionIndex"] as? String

        guard let transaction = Transaction.fromJSON(json) else { return nil }
        self.transaction = transaction
        if bn != nil {
            blockNumber = BigUInt(bn!.stripHexPrefix(), radix: 16)
        }
        if ti != nil {
            transactionIndex = BigUInt(ti!.stripHexPrefix(), radix: 16)
        }
    }
}

public struct TransactionReceipt: Decodable {
    var transactionHash: Data
    var blockHash: Data
    var blockNumber: BigUInt
    var transactionIndex: BigUInt
    var contractAddress: EthereumAddress?
    var cumulativeGasUsed: BigUInt
    var gasUsed: BigUInt
    var logs: [EventLog]
    public var status: TXStatus
    var logsBloom: EthereumBloomFilter?

    public enum TXStatus {
        case ok
        case failed
        case notYetProcessed
    }

    enum CodingKeys: String, CodingKey {
        case blockHash
        case blockNumber
        case transactionHash
        case transactionIndex
        case contractAddress
        case cumulativeGasUsed
        case gasUsed
        case logs
        case logsBloom
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let blockNumber = try decodeHexToBigUInt(container, key: .blockNumber) else { throw DecodeError.typeMismatch }
        self.blockNumber = blockNumber

        guard let blockHash = try decodeHexToData(container, key: .blockHash) else { throw DecodeError.typeMismatch }
        self.blockHash = blockHash

        guard let transactionIndex = try decodeHexToBigUInt(container, key: .transactionIndex) else { throw DecodeError.typeMismatch }
        self.transactionIndex = transactionIndex

        guard let transactionHash = try decodeHexToData(container, key: .transactionHash) else { throw DecodeError.typeMismatch }
        self.transactionHash = transactionHash

        let contractAddress = try container.decodeIfPresent(EthereumAddress.self, forKey: .contractAddress)
        if contractAddress != nil {
            self.contractAddress = contractAddress
        }

        guard let cumulativeGasUsed = try decodeHexToBigUInt(container, key: .cumulativeGasUsed) else { throw DecodeError.typeMismatch }
        self.cumulativeGasUsed = cumulativeGasUsed

        guard let gasUsed = try decodeHexToBigUInt(container, key: .gasUsed) else { throw DecodeError.typeMismatch }
        self.gasUsed = gasUsed

        let status = try decodeHexToBigUInt(container, key: .status, allowOptional: true)
        if status == nil {
            self.status = TXStatus.notYetProcessed
        } else if status == 1 {
            self.status = TXStatus.ok
        } else {
            self.status = TXStatus.failed
        }

        if let logsData = try decodeHexToData(container, key: .logsBloom, allowOptional: true), !logsData.isEmpty {
            self.logsBloom = EthereumBloomFilter(logsData)
        }

        let logs = try container.decode([EventLog].self, forKey: .logs)
        self.logs = logs
    }

    init(transactionHash: Data, blockHash: Data, blockNumber: BigUInt, transactionIndex: BigUInt, contractAddress: EthereumAddress?, cumulativeGasUsed: BigUInt, gasUsed: BigUInt, logs: [EventLog], status: TXStatus, logsBloom: EthereumBloomFilter?) {
        self.transactionHash = transactionHash
        self.blockHash = blockHash
        self.blockNumber = blockNumber
        self.transactionIndex = transactionIndex
        self.contractAddress = contractAddress
        self.cumulativeGasUsed = cumulativeGasUsed
        self.gasUsed = gasUsed
        self.logs = logs
        self.status = status
        self.logsBloom = logsBloom
    }

    init?(_ json: [String: AnyObject]) {
        guard let th = json["transactionHash"] as? String else { return nil }
        guard let transactionHash = Data.fromHex(th) else { return nil }
        self.transactionHash = transactionHash
        guard let bh = json["blockHash"] as? String else { return nil }
        guard let blockHash = Data.fromHex(bh) else { return nil }
        self.blockHash = blockHash
        guard let bn = json["blockNumber"] as? String else { return nil }
        guard let ti = json["transactionIndex"] as? String else { return nil }
        let ca = json["contractAddress"] as? String
        guard let cgu = json["cumulativeGasUsed"] as? String else { return nil }
        guard let gu = json["gasUsed"] as? String else { return nil }
        guard let ls = json["logs"] as? [[String: AnyObject]] else { return nil }
        let lbl = json["logsBloom"] as? String
        let st = json["status"] as? String

        guard let bnUnwrapped = BigUInt(bn.stripHexPrefix(), radix: 16) else { return nil }
        blockNumber = bnUnwrapped
        guard let tiUnwrapped = BigUInt(ti.stripHexPrefix(), radix: 16) else { return nil }
        transactionIndex = tiUnwrapped
        if ca != nil {
            contractAddress = EthereumAddress(ca!.addHexPrefix())
        }
        guard let cguUnwrapped = BigUInt(cgu.stripHexPrefix(), radix: 16) else { return nil }
        cumulativeGasUsed = cguUnwrapped
        guard let guUnwrapped = BigUInt(gu.stripHexPrefix(), radix: 16) else { return nil }
        gasUsed = guUnwrapped
        var allLogs = [EventLog]()
        for l in ls {
            guard let log = EventLog(l) else { return nil }
            allLogs.append(log)
        }
        logs = allLogs
        if st == nil {
            status = TXStatus.notYetProcessed
        } else if st == "0x1" {
            status = TXStatus.ok
        } else {
            status = TXStatus.failed
        }

        if let logsData = lbl.flatMap({ Data.fromHex($0) }), !logsData.isEmpty {
            logsBloom = EthereumBloomFilter(logsData)
        }
    }

    static func notProcessed(transactionHash: Data) -> TransactionReceipt {
        let receipt = TransactionReceipt.init(transactionHash: transactionHash, blockHash: Data(), blockNumber: BigUInt(0), transactionIndex: BigUInt(0), contractAddress: nil, cumulativeGasUsed: BigUInt(0), gasUsed: BigUInt(0), logs: [EventLog](), status: .notYetProcessed, logsBloom: nil)
        return receipt
    }
}

extension EthereumAddress: Decodable, Encodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        self.init(stringValue)!
    }
    public func encode(to encoder: Encoder) throws {
        let value = self.address.lowercased()
        var signleValuedCont = encoder.singleValueContainer()
        try signleValuedCont.encode(value)
    }
}

public struct EventLog: Codable {
    public var address: EthereumAddress
    public var blockHash: Data
    public var blockNumber: BigUInt
    public var data: Data
    public var logIndex: BigUInt
    public var removed: Bool
    public var topics: [Data]
    public var transactionHash: Data
    public var transactionIndex: BigUInt

    enum CodingKeys: String, CodingKey {
        case address
        case blockHash
        case blockNumber
        case data
        case logIndex
        case removed
        case topics
        case transactionHash
        case transactionIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let address = try container.decode(EthereumAddress.self, forKey: .address)
        self.address = address

        guard let blockNumber = try decodeHexToBigUInt(container, key: .blockNumber) else { throw DecodeError.typeMismatch }
        self.blockNumber = blockNumber

        guard let blockHash = try decodeHexToData(container, key: .blockHash) else { throw DecodeError.typeMismatch }
        self.blockHash = blockHash

        guard let transactionIndex = try decodeHexToBigUInt(container, key: .transactionIndex) else { throw DecodeError.typeMismatch }
        self.transactionIndex = transactionIndex

        guard let transactionHash = try decodeHexToData(container, key: .transactionHash) else { throw DecodeError.typeMismatch }
        self.transactionHash = transactionHash

        guard let data = try decodeHexToData(container, key: .data) else { throw DecodeError.typeMismatch }
        self.data = data

        guard let logIndex = try decodeHexToBigUInt(container, key: .logIndex) else { throw DecodeError.typeMismatch }
        self.logIndex = logIndex

        let removed = try decodeHexToBigUInt(container, key: .removed, allowOptional: true)
        if removed == 1 {
            self.removed = true
        } else {
            self.removed = false
        }

        let topicsStrings = try container.decode([String].self, forKey: .topics)
        var allTopics = [Data]()
        for top in topicsStrings {
            guard let topic = Data.fromHex(top) else { throw DecodeError.typeMismatch }
            allTopics.append(topic)
        }
        self.topics = allTopics
    }

    public init? (_ json: [String: AnyObject]) {
        guard let ad = json["address"] as? String else { return nil }
        guard let d = json["data"] as? String else { return nil }
        guard let li = json["logIndex"] as? String else { return nil }
        let rm = json["removed"] as? Int ?? 0
        guard let tpc = json["topics"] as? [String] else { return nil }
        guard let addr = EthereumAddress(ad) else { return nil }
        address = addr
        guard let txhash = json["transactionHash"] as? String else { return nil }
        let hash = Data.fromHex(txhash)
        if hash != nil {
            transactionHash = hash!
        } else {
            transactionHash = Data()
        }
        data = Data.fromHex(d)!
        guard let liUnwrapped = BigUInt(li.stripHexPrefix(), radix: 16) else { return nil }
        logIndex = liUnwrapped
        removed = rm == 1 ? true : false
        var tops = [Data]()
        for t in tpc {
            guard let topic = Data.fromHex(t) else { return nil }
            tops.append(topic)
        }
        topics = tops
        // TODO
        blockNumber = 0
        blockHash = Data()
        transactionIndex = 0
    }
}

enum TransactionInBlock: Decodable {
    case hash(Data)
    case transaction(Transaction)
    case null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let string = try? value.decode(String.self) {
            guard let d = Data.fromHex(string) else { throw DecodeError.typeMismatch }
            self = .hash(d)
        } else if let dict = try? value.decode([String: String].self) {
//            guard let t = try? EthereumTransaction(from: decoder) else {throw Web3Error.dataError}
            guard let t = Transaction.fromJSON(dict) else { throw DecodeError.typeMismatch }
            self = .transaction(t)
        } else {
            self = .null
        }
    }

    public init?(_ data: AnyObject) {
        if let string = data as? String {
            guard let d = Data.fromHex(string) else { return nil }
            self = .hash(d)
        } else if let dict = data as? [String: AnyObject] {
            guard let t = Transaction.fromJSON(dict) else { return nil }
            self = .transaction(t)
        } else {
            return nil
        }
    }
}

public struct Block: Decodable {
    public var number: BigUInt
    public var hash: Data
    public var parentHash: Data
    public var nonce: Data?
    public var sha3Uncles: Data
    public var logsBloom: EthereumBloomFilter?
    public var transactionsRoot: Data
    public var stateRoot: Data
    public var receiptsRoot: Data
    public var miner: EthereumAddress?
    public var difficulty: BigUInt
    public var totalDifficulty: BigUInt
    public var extraData: Data
    public var size: BigUInt
    public var gasLimit: BigUInt
    public var gasUsed: BigUInt
    public var timestamp: Date
    var transactions: [TransactionInBlock]
    public var uncles: [Data]

    enum CodingKeys: String, CodingKey {
        case number
        case hash
        case parentHash
        case nonce
        case sha3Uncles
        case logsBloom
        case transactionsRoot
        case stateRoot
        case receiptsRoot
        case miner
        case difficulty
        case totalDifficulty
        case extraData
        case size
        case gasLimit
        case gasUsed
        case timestamp
        case transactions
        case uncles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let number = try decodeHexToBigUInt(container, key: .number) else { throw DecodeError.typeMismatch }
        self.number = number

        guard let hash = try decodeHexToData(container, key: .hash) else { throw DecodeError.typeMismatch }
        self.hash = hash

        guard let parentHash = try decodeHexToData(container, key: .parentHash) else { throw DecodeError.typeMismatch }
        self.parentHash = parentHash

        let nonce = try decodeHexToData(container, key: .nonce, allowOptional: true)
        self.nonce = nonce

        guard let sha3Uncles = try decodeHexToData(container, key: .sha3Uncles) else { throw DecodeError.typeMismatch }
        self.sha3Uncles = sha3Uncles

        let logsBloomData = try decodeHexToData(container, key: .logsBloom, allowOptional: true)
        var bloom: EthereumBloomFilter?
        if logsBloomData != nil {
            bloom = EthereumBloomFilter(logsBloomData!)
        }
        self.logsBloom = bloom

        guard let transactionsRoot = try decodeHexToData(container, key: .transactionsRoot) else { throw DecodeError.typeMismatch }
        self.transactionsRoot = transactionsRoot

        guard let stateRoot = try decodeHexToData(container, key: .stateRoot) else { throw DecodeError.typeMismatch }
        self.stateRoot = stateRoot

        guard let receiptsRoot = try decodeHexToData(container, key: .receiptsRoot) else { throw DecodeError.typeMismatch }
        self.receiptsRoot = receiptsRoot

        let minerAddress = try? container.decode(String.self, forKey: .miner)
        var miner: EthereumAddress?
        if minerAddress != nil {
            guard let minr = EthereumAddress(minerAddress!) else { throw DecodeError.typeMismatch }
            miner = minr
        }
        self.miner = miner

        guard let difficulty = try decodeHexToBigUInt(container, key: .difficulty) else { throw DecodeError.typeMismatch }
        self.difficulty = difficulty

        guard let totalDifficulty = try decodeHexToBigUInt(container, key: .totalDifficulty) else { throw DecodeError.typeMismatch }
        self.totalDifficulty = totalDifficulty

        guard let extraData = try decodeHexToData(container, key: .extraData) else { throw DecodeError.typeMismatch }
        self.extraData = extraData

        guard let size = try decodeHexToBigUInt(container, key: .size) else { throw DecodeError.typeMismatch }
        self.size = size

        guard let gasLimit = try decodeHexToBigUInt(container, key: .gasLimit) else { throw DecodeError.typeMismatch }
        self.gasLimit = gasLimit

        guard let gasUsed = try decodeHexToBigUInt(container, key: .gasUsed) else { throw DecodeError.typeMismatch }
        self.gasUsed = gasUsed

        let timestampString = try container.decode(String.self, forKey: .timestamp).stripHexPrefix()
        guard let timestampInt = UInt64(timestampString, radix: 16) else { throw DecodeError.typeMismatch }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampInt))
        self.timestamp = timestamp

        let transactions = try container.decode([TransactionInBlock].self, forKey: .transactions)
        self.transactions = transactions

        let unclesStrings = try container.decode([String].self, forKey: .uncles)
        var uncles = [Data]()
        for str in unclesStrings {
            guard let d = Data.fromHex(str) else { throw DecodeError.typeMismatch }
            uncles.append(d)
        }
        self.uncles = uncles
    }
}

public struct EventParserResult: EventParserResultProtocol {
    public var eventName: String
    public var transactionReceipt: TransactionReceipt?
    public var contractAddress: EthereumAddress
    public var decodedResult: [String: Any]
    public var eventLog: EventLog?

    public init (eventName: String, transactionReceipt: TransactionReceipt?, contractAddress: EthereumAddress, decodedResult: [String: Any]) {
        self.eventName = eventName
        self.transactionReceipt = transactionReceipt
        self.contractAddress = contractAddress
        self.decodedResult = decodedResult
        self.eventLog = nil
    }
}

public struct TransactionSendingResult {
    var transaction: Transaction
    public var hash: String
}
