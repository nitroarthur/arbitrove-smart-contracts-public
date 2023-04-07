pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "@/FactoryArbitrove.sol";

interface _CheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
}

contract VyperDeployer {
    /// @notice Initializes cheat codes in order to use ffi to compile Vyper contracts
    _CheatCodes cheatCodes =
        _CheatCodes(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

    ///@notice Compiles a Vyper contract and returns the address that the contract was deployeod to
    ///@notice If deployment fails, an error will be thrown
    ///@param fileName - The file name of the Vyper contract. For example, the file name for "SimpleStore.vy" is "SimpleStore"
    ///@return deployedAddress - The address that the contract was deployed to

    function deployContract(string memory fileName) public returns (address) {
        ///@notice create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = string.concat(fileName);

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory bytecode = cheatCodes.ffi(cmds);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "VyperDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }

    ///@notice Compiles a Vyper contract with constructor arguments and returns the address that the contract was deployeod to
    ///@notice If deployment fails, an error will be thrown
    ///@param fileName - The file name of the Vyper contract. For example, the file name for "SimpleStore.vy" is "SimpleStore"
    ///@return deployedAddress - The address that the contract was deployed to
    function deployContract(
        string memory fileName,
        bytes calldata args
    ) public returns (address) {
        ///@notice create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = string.concat(fileName);

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory _bytecode = cheatCodes.ffi(cmds);

        //add args to the deployment bytecode
        bytes memory bytecode = abi.encodePacked(_bytecode, args);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "VyperDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }
}

struct MintRequest {
    uint256 inputTokenAmount;
    uint256 minAlpAmount;
    IERC20 coin;
    address requester;
    uint256 expire;
}

struct BurnRequest {
    uint256 maxAlpAmount;
    uint256 outputTokenAmount;
    IERC20 coin;
    address requester;
    uint256 expire;
}

struct DepositWithdrawalParams {
    uint256 coinPositionInCPU;
    uint256 _amount;
    CoinPriceUSD[] cpu;
    uint256 expireTimestamp;
}

struct OracleParams {
    CoinPriceUSD[] cpu;
    uint256 expireTimestamp;
}

interface Router {
    function submitMintRequest(MintRequest calldata mr) external;

    function submitBurnRequest(BurnRequest calldata br) external;

    function processMintRequest(OracleParams calldata dwp) external;

    function processBurnRequest(OracleParams calldata dwp) external;

    function cancelMintRequest(bool refund) external;

    function acquireLock() external;

    function releaseLock() external;

    function rescueStuckTokens(IERC20 token, uint256 amount) external;

    function owner() external view returns (address);

    function initialize(address, address, address) external;

    function setFee(uint256) external;

    function setFeeDenominator(uint256) external;
}

contract DeployFactory is Script, VyperDeployer {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 blockCap = vm.envUint("BLOCK_CAP");
        uint256 poolRatioDenominator = vm.envUint("POOL_RATIO_DENOMINATOR");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        FactoryArbitrove factory = new FactoryArbitrove();
        address routerAddress = deployContract("src/contracts/Router.vy");
        Router(routerAddress).initialize(
            factory.vaultAddress(),
            factory.addressRegistryAddress(),
            deployer
        );
        Router(routerAddress).setFee(5);
        Router(routerAddress).setFeeDenominator(1000);
        AddressRegistry(factory.addressRegistryAddress()).init(
            FeeOracle(factory.feeOracleAddress()),
            routerAddress
        );
        Vault(payable(factory.vaultAddress())).init829{value: 1e15}(
            AddressRegistry(factory.addressRegistryAddress())
        );
        Vault(payable(factory.vaultAddress())).setBlockCap(blockCap);
        Vault(payable(factory.vaultAddress())).setPoolRatioDenominator(
            poolRatioDenominator
        );
        FeeOracle(factory.feeOracleAddress()).init(20, 0);

        console.log("router: ");
        console.log(routerAddress);
        console.log("addressRegistry: ");
        console.log(factory.addressRegistryAddress());
        console.log("feeOracle: ");
        console.log(factory.feeOracleAddress());
        console.log("vault: ");
        console.log(factory.vaultAddress());

        vm.stopBroadcast();
    }
}
