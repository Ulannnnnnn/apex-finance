// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PoolFactory} from "../src/core/PoolFactory.sol";

contract PoolFactoryTest is Test {
    PoolFactory public factory;
    address public owner = address(1);
    address public tokenA = address(100);
    address public tokenB = address(200);

    function setUp() public {
        vm.prank(owner);
        factory = new PoolFactory(owner);
    }

    function test_CreatePoolStandard() public {
        vm.prank(owner);
        address pool = factory.createPoolStandard(tokenA, tokenB);

        assertTrue(pool != address(0));
        assertEq(factory.getPool(tokenA, tokenB), pool);
    }

    function test_CreatePoolDeterministicAndPredict() public {
        bytes32 salt = keccak256(abi.encodePacked("pool-salt-1"));

        // 1. Предсказываем адрес пула ДО его создания
        address predictedAddress = factory.predictDeterministicAddress(tokenA, tokenB, salt);

        // 2. Деплоим через CREATE2
        vm.prank(owner);
        address actualPool = factory.createPoolDeterministic(tokenA, tokenB, salt);

        // 3. Проверяем, совпал ли реальный адрес с предсказанным
        assertEq(actualPool, predictedAddress);
        assertEq(factory.getPool(tokenA, tokenB), actualPool);
    }
}
