// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MultiBettingPool is Ownable, ReentrancyGuard {
    constructor() Ownable(msg.sender) {}
    
    // Participant Struct to track participant details
    struct Participant {
        address user;
        uint256 amount;
        uint256 timestamp;
        uint256 currentTokenPriceAtEntry;
    }

    // Pool configuration details
    struct PoolConfig {
        bytes32 uuid;
        string name;
        string rewardTokenName;
        address rewardToken;
        uint256 entryAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 basePrice;
        uint256 currentPriceOfToken;
        uint256 upperCircuitLimit;
        uint256 lowerCircuitLimit;
        uint256 totalPoolAmount;
        uint256 createdAtEpoch;
        Participant[] participants;
        bool exists;
    }

    // Mapping to store all pools by their UUID
    mapping(bytes32 => PoolConfig) public pools;

    // Array to keep track of all pool UUIDs
    bytes32[] public poolUuids;

    // Events
    event PoolCreated(
        bytes32 indexed uuid, 
        string name, 
        address rewardToken, 
        uint256 entryAmount, 
        uint256 startTime, 
        uint256 endTime, 
        uint256 basePrice,
        uint256 upperCircuitLimit,
        uint256 lowerCircuitLimit,
        uint256 createdAtEpoch
    );
    event ParticipantEntered(
        bytes32 indexed poolUuid, 
        address participant, 
        uint256 amount, 
        uint256 currentTokenPrice
    );
    event PoolFundsWithdrawn(
        bytes32 indexed poolUuid, 
        address[] recipients, 
        uint256[] amounts
    );

    // Function to create a new pool (Only Admin)
    function createPool(
        bytes32 _uuid,
        string memory _name,
        string memory _rewardTokenName,
        address _rewardToken,
        uint256 _entryAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _basePrice,
        uint256 _currentPriceOfToken,
        uint256 _upperCircuitLimit,
        uint256 _lowerCircuitLimit
    ) external onlyOwner {
        // Ensure UUID is unique
        require(!pools[_uuid].exists, "Pool with this UUID already exists");

        // Validate circuit limits
        require(_upperCircuitLimit >= _currentPriceOfToken, "Upper limit must be >= current price");
        require(_lowerCircuitLimit <= _currentPriceOfToken, "Lower limit must be <= current price");

        // Create new pool
        PoolConfig storage newPool = pools[_uuid];
        newPool.uuid = _uuid;
        newPool.name = _name;
        newPool.rewardTokenName = _rewardTokenName;
        newPool.rewardToken = _rewardToken;
        newPool.entryAmount = _entryAmount;
        newPool.startTime = _startTime;
        newPool.endTime = _endTime;
        newPool.basePrice = _basePrice;
        newPool.currentPriceOfToken = _currentPriceOfToken;
        newPool.upperCircuitLimit = _upperCircuitLimit;
        newPool.lowerCircuitLimit = _lowerCircuitLimit;
        newPool.totalPoolAmount = 0;
        newPool.createdAtEpoch = block.timestamp;
        newPool.exists = true;

        // Add UUID to tracking array
        poolUuids.push(_uuid);

        emit PoolCreated(
            _uuid, 
            _name, 
            _rewardToken, 
            _entryAmount, 
            _startTime, 
            _endTime, 
            _basePrice,
            _upperCircuitLimit,
            _lowerCircuitLimit,
            newPool.createdAtEpoch
        );
    }

    // Function for users to enter a specific pool
    function enterPool(
        bytes32 _poolUuid, 
        uint256 _currentTokenPrice
    ) external nonReentrant {
        // Retrieve the pool
        PoolConfig storage pool = pools[_poolUuid];

        // Check pool exists and is active
        require(pool.exists, "Pool does not exist");
        require(block.timestamp >= pool.startTime, "Pool not started");
        require(block.timestamp <= pool.endTime, "Pool ended");

        // Check token price is within circuit limits
        require(
            _currentTokenPrice >= pool.lowerCircuitLimit && 
            _currentTokenPrice <= pool.upperCircuitLimit, 
            "Token price out of circuit limits"
        );

        uint256 amount = pool.entryAmount;
        IERC20 rewardToken = IERC20(pool.rewardToken);

        // Transfer reward token from user to contract
        require(
            rewardToken.transferFrom(msg.sender, address(this), amount), 
            "Transfer failed"
        );

        // Add participant to the pool
        pool.participants.push(Participant({
            user: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            currentTokenPriceAtEntry: _currentTokenPrice
        }));

        // Update total pool amount and current token price
        pool.totalPoolAmount += amount;
        pool.currentPriceOfToken = _currentTokenPrice;

        emit ParticipantEntered(
            _poolUuid, 
            msg.sender, 
            amount, 
            _currentTokenPrice
        );
    }

    // Function to withdraw pool funds
    function withdrawPoolFunds(
        bytes32 _poolUuid, 
        address[] memory _recipients
    ) external onlyOwner {
        PoolConfig storage pool = pools[_poolUuid];
        require(pool.exists, "Pool does not exist");
        require(block.timestamp > pool.endTime, "Pool has not ended");
        
        IERC20 rewardToken = IERC20(pool.rewardToken);
        uint256 totalAmount = pool.totalPoolAmount;

        // Validate recipients and distribute funds
        if (_recipients.length == 1) {
            // Single recipient gets entire pool amount
            require(rewardToken.transfer(_recipients[0], totalAmount), "Transfer failed");
            
            emit PoolFundsWithdrawn(
                _poolUuid, 
                _recipients, 
                new uint256[](1)
            );
        } else {
            // Multiple recipients split pool amount equally
            uint256 amountPerRecipient = totalAmount / _recipients.length;
            uint256[] memory distributedAmounts = new uint256[](_recipients.length);

            for (uint256 i = 0; i < _recipients.length; i++) {
                require(rewardToken.transfer(_recipients[i], amountPerRecipient), "Transfer failed");
                distributedAmounts[i] = amountPerRecipient;
            }

            emit PoolFundsWithdrawn(
                _poolUuid, 
                _recipients, 
                distributedAmounts
            );
        }

        // Reset pool total amount
        pool.totalPoolAmount = 0;
        delete pool.participants;
    }

    // Utility function to get a specific pool
    function getPool(bytes32 _uuid) external view returns (PoolConfig memory) {
        require(pools[_uuid].exists, "Pool does not exist");
        return pools[_uuid];
    }

    // Utility function to get all pool UUIDs
    function getAllPoolUuids() external view returns (bytes32[] memory) {
        return poolUuids;
    }

    // Utility function to get participants of a specific pool
    function getPoolParticipants(bytes32 _poolUuid) external view returns (Participant[] memory) {
        require(pools[_poolUuid].exists, "Pool does not exist");
        return pools[_poolUuid].participants;
    }
}