// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Простой минимальный контракт пула (заглушка для демонстрации деплоя)
 */
contract LiquidityPool {
    address public factory;
    address public tokenA;
    address public tokenB;

    constructor(address _tokenA, address _tokenB) {
        factory = msg.sender;
        tokenA = _tokenA;
        tokenB = _tokenB;
    }
}

/**
 * @title PoolFactory
 * @dev Фабрика пулов, реализующая деплой через CREATE и CREATE2 строго по ТЗ.
 */
contract PoolFactory is Ownable {
    // Массив всех созданных пулов
    address[] public allPools;

    // Маппинг для быстрого поиска пула по двум токенам: ТокенА => ТокенБ => АдресПула
    mapping(address => mapping(address => address)) public getPool;

    event PoolCreated(address indexed tokenA, address indexed tokenB, address poolAddress, uint256 poolIndex);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @dev Деплой пула через стандартный оператор CREATE.
     * Адрес зависит от nonce фабрики.
     */
    function createPoolStandard(address tokenA, address tokenB) external onlyOwner returns (address pool) {
        require(tokenA != tokenB, "PoolFactory: Identical tokens");
        require(getPool[tokenA][tokenB] == address(0), "PoolFactory: Pool exists");

        // Стандартный CREATE
        pool = address(new LiquidityPool(tokenA, tokenB));

        getPool[tokenA][tokenB] = pool;
        getPool[tokenB][tokenA] = pool; // В обе стороны
        allPools.push(pool);

        emit PoolCreated(tokenA, tokenB, pool, allPools.length - 1);
    }

    /**
     * @dev Деплой пула через CREATE2.
     * Адрес детерминирован и зависит только от байткода, токенов и соли (salt).
     */
    function createPoolDeterministic(address tokenA, address tokenB, bytes32 salt)
        external
        onlyOwner
        returns (address pool)
    {
        require(tokenA != tokenB, "PoolFactory: Identical tokens");
        require(getPool[tokenA][tokenB] == address(0), "PoolFactory: Pool exists");

        // Подготавливаем байткод создания контракта вместе с аргументами конструктора
        bytes memory bytecode = abi.encodePacked(type(LiquidityPool).creationCode, abi.encode(tokenA, tokenB));

        // Вызов CREATE2 через встроенный ассемблер Solidity
        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        require(pool != address(0), "PoolFactory: Deploy failed");

        getPool[tokenA][tokenB] = pool;
        getPool[tokenB][tokenA] = pool;
        allPools.push(pool);

        emit PoolCreated(tokenA, tokenB, pool, allPools.length - 1);
    }

    /**
     * @dev Вью-функция для предсказания адреса CREATE2 до его фактического деплоя в сеть.
     */
    function predictDeterministicAddress(address tokenA, address tokenB, bytes32 salt) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(type(LiquidityPool).creationCode, abi.encode(tokenA, tokenB));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    function getPoolsCount() external view returns (uint256) {
        return allPools.length;
    }
}
