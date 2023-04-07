# @version 0.3.7

struct CoinPriceUSD:
    coin: address
    price: uint256

struct DepositWithdrawalParams:
    coinPositionInCPU: uint256
    _amount: uint256
    cpu: DynArray[CoinPriceUSD, 50]
    expireTimestamp: uint256

struct OracleParams:
    cpu: DynArray[CoinPriceUSD, 50]
    expireTimestamp: uint256

interface FeeOracle:
    def isInTarget(coin: address) -> bool: view

interface AddressRegistry:
    def getCoinToStrategy(a: address) -> DynArray[address,100]: view
    def feeOracle() -> FeeOracle: view

interface IERC20:
    def transferFrom(a: address, b: address, c: uint256) -> bool: nonpayable
    def balanceOf(a: address) -> uint256: view
    def transfer(a: address, c: uint256) -> bool: nonpayable

interface IVault:
    def deposit(dwp: DepositWithdrawalParams): payable
    def withdraw(dwp: DepositWithdrawalParams): payable
    def claimDebt(a: address, b: uint256): nonpayable
    def transferFrom(a: address, b: address, c: uint256) -> bool: nonpayable
    

struct MintRequest:
    inputTokenAmount: uint256
    minAlpAmount: uint256
    coin: IERC20
    requester: address
    expire: uint256

struct BurnRequest:
    maxAlpAmount: uint256
    outputTokenAmount: uint256
    coin: IERC20
    requester: address
    expire: uint256

mintQueue: DynArray[MintRequest, 200]
burnQueue: DynArray[BurnRequest, 200]
owner: public(address)
darkOracle: public(address)
fee: public(uint256)
feeDenominator: public(uint256)
lock: bool
vault: address
addressRegistry: AddressRegistry
event MintRequestAdded:
    mr: MintRequest
event BurnRequestAdded:
    br: BurnRequest
event MintRequestProcessed:
    op: OracleParams
event BurnRequestProcessed:
    op: OracleParams

@external
def initialize(_vault: address, _addressRegistry: AddressRegistry, _darkOracle: address):
    assert self.owner == empty(address)
    self.owner = msg.sender
    self.vault = _vault
    self.addressRegistry = _addressRegistry
    self.darkOracle = _darkOracle

@external
def reinitialize(_vault: address, _addressRegistry: AddressRegistry, _darkOracle: address):
    assert msg.sender == self.owner
    self.owner = msg.sender
    self.vault = _vault
    self.addressRegistry = _addressRegistry
    self.darkOracle = _darkOracle

@external
def setFee(_fee: uint256):
    assert msg.sender == self.owner
    self.fee = _fee

@external
def setFeeDenominator(_feeDenominator: uint256):
    assert msg.sender == self.owner
    self.feeDenominator = _feeDenominator

@internal
def getCoinPositionInCPU(cpu: DynArray[CoinPriceUSD, 50], coin: address) -> uint256:
    for i in range(50):
        if i < len(cpu) and cpu[i].coin == coin:
            return i
    raise "False"

# request vault to mint ALP tokens and sends payment tokens to vault afterwards
@external 
@nonreentrant("router")
def processMintRequest(dwp: OracleParams):
    assert self.addressRegistry.feeOracle().isInTarget(dwp.cpu[0].coin)
    assert msg.sender == self.darkOracle
    if not self.lock:
        raise "Not locked"
    if not len(self.mintQueue) > 0:
        raise "No mint request"
    mr: MintRequest = self.mintQueue.pop()
    if block.timestamp > mr.expire:
        raise "Request expired"
    before_balance: uint256 = IERC20(self.vault).balanceOf(self)
    _amountToMint: uint256 = mr.inputTokenAmount
    if self.fee > 0:
        if self.feeDenominator < self.fee:
            raise "invalid feeDenominator"
        _amountToMint = _amountToMint * (self.feeDenominator - self.fee) / self.feeDenominator
    IVault(self.vault).deposit(DepositWithdrawalParams({
        coinPositionInCPU: self.getCoinPositionInCPU(dwp.cpu, mr.coin.address),
        _amount: _amountToMint,
        cpu: dwp.cpu,
        expireTimestamp: dwp.expireTimestamp
    }))
    after_balance: uint256 = IERC20(self.vault).balanceOf(self)
    delta: uint256 = after_balance - before_balance
    if delta < mr.minAlpAmount:
        raise "Not enough ALP minted"
    if mr.coin.address == convert(0, address):
        send(self.vault, _amountToMint)
    else:
        assert mr.coin.transfer(self.vault, _amountToMint)
    assert IERC20(self.vault).transfer(mr.requester, delta)
    log MintRequestProcessed(dwp)

@external
@view
def mintQueueLength() -> uint256:
    return len(self.mintQueue)

@external
@view
def burnQueueLength() -> uint256:
    return len(self.burnQueue)

@external
@nonreentrant("router")
def cancelMintRequest(refund: bool):
    assert self.lock
    mr: MintRequest = self.mintQueue.pop()
    assert msg.sender == self.darkOracle or mr.expire < block.timestamp
    if refund:
        if mr.coin.address == convert(0, address):
            send(mr.requester, mr.inputTokenAmount)
        else:
            assert mr.coin.transfer(mr.requester, mr.inputTokenAmount)

# request vault to burn ALP tokens and mint debt tokens to requester afterwards.
@external 
@nonreentrant("router")
def processBurnRequest(dwp: OracleParams):
    assert self.addressRegistry.feeOracle().isInTarget(dwp.cpu[0].coin)
    assert msg.sender == self.darkOracle
    if not self.lock:
        raise "Not locked"
    if not len(self.burnQueue) > 0:
        raise "No burn request"
    br: BurnRequest = self.burnQueue.pop()
    if block.timestamp > br.expire:
        raise "Request expired"
    before_balance: uint256 = IERC20(self.vault).balanceOf(self)
    _amountToBurn: uint256 = br.outputTokenAmount
    if self.fee > 0:
        if self.feeDenominator < self.fee:
            raise "invalid feeDenominator"
        _amountToBurn = _amountToBurn * (self.feeDenominator - self.fee) / self.feeDenominator
    coinPositionInCPU: uint256 = self.getCoinPositionInCPU(dwp.cpu, br.coin.address)
    IVault(self.vault).withdraw(DepositWithdrawalParams({
        coinPositionInCPU: coinPositionInCPU,
        _amount: _amountToBurn,
        cpu: dwp.cpu,
        expireTimestamp: dwp.expireTimestamp
    }))
    after_balance: uint256 = IERC20(self.vault).balanceOf(self)
    delta: uint256 = before_balance - after_balance
    if delta > br.maxAlpAmount:
        raise "Too much ALP burned"
    IVault(self.vault).claimDebt(dwp.cpu[coinPositionInCPU].coin, _amountToBurn)
    if br.coin.address == convert(0, address):
        send(br.requester, _amountToBurn)
    else:
        assert br.coin.transfer(br.requester, _amountToBurn)
    assert IERC20(self.vault).transfer(br.requester, br.maxAlpAmount - delta)
    log BurnRequestProcessed(dwp)

@external
@nonreentrant("router")
def refundBurnRequest():
    assert self.lock
    br: BurnRequest = self.burnQueue.pop()
    assert msg.sender == self.darkOracle or br.expire < block.timestamp
    assert IERC20(self.vault).transfer(br.requester, br.maxAlpAmount)

# lock submitting new requests before crunching queue
@external 
def acquireLock():
    assert msg.sender == self.darkOracle
    self.lock = True

@external 
def releaseLock():
    assert msg.sender == self.darkOracle
    self.lock = False

@external
@nonreentrant("router")
@payable
def submitMintRequest(mr: MintRequest):
    
    assert self.addressRegistry.feeOracle().isInTarget(mr.coin.address)
    assert self.lock == False
    assert mr.requester == msg.sender
    self.mintQueue.append(mr)
    if convert(0, address) != mr.coin.address:
        assert mr.coin.transferFrom(msg.sender, self, mr.inputTokenAmount)
    else:
        assert msg.value == mr.inputTokenAmount
    log MintRequestAdded(mr)


@external
@nonreentrant("router")
def submitBurnRequest(br: BurnRequest):
    assert self.addressRegistry.feeOracle().isInTarget(br.coin.address)
    assert self.lock == False
    assert br.requester == msg.sender
    self.burnQueue.append(br)
    assert IERC20(self.vault).transferFrom(msg.sender, self, br.maxAlpAmount)
    log BurnRequestAdded(br)

@external
@nonreentrant("router")
def rescueStuckTokens(token: IERC20, amount: uint256):
    assert msg.sender == self.owner
    assert token.transfer(self.owner, amount)

@external
def suicide():
    assert msg.sender == self.owner
    selfdestruct(self.owner)