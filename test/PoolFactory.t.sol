// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PoolFactory} from "../src/core/PoolFactory.sol";

contract PoolFactoryTest is Test {
    PoolFactory public factory;
    address public owner = address(1);
    address public user1 = address(2);
    address public tokenA = address(100);
    address public tokenB = address(200);

    function setUp() public {
        vm.prank(owner);
        factory = new PoolFactory(owner);
    }

    // --- Блок 4: Тесты Фабрики (6 тестов) ---

    function test_CreatePoolStandard() public {
        vm.prank(owner);
        address pool = factory.createPoolStandard(tokenA, tokenB);

        assertTrue(pool != address(0));
        assertEq(factory.getPool(tokenA, tokenB), pool);
        assertEq(factory.getPoolsCount(), 1);
    }

    function test_CreatePoolDeterministicAndPredict() public {
        bytes32 salt = keccak256(abi.encodePacked("pool-salt-1"));
        address predictedAddress = factory.predictDeterministicAddress(tokenA, tokenB, salt);

        vm.prank(owner);
        address actualPool = factory.createPoolDeterministic(tokenA, tokenB, salt);

        assertEq(actualPool, predictedAddress);
        assertEq(factory.getPool(tokenA, tokenB), actualPool);
    }

    function test_RevertWhen_CreateWithIdenticalTokens() public {
        vm.startPrank(owner);
        vm.expectRevert("PoolFactory: Identical tokens");
        factory.createPoolStandard(tokenA, tokenA);

        vm.expectRevert("PoolFactory: Identical tokens");
        factory.createPoolDeterministic(tokenA, tokenA, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertWhen_PoolAlreadyExists() public {
        vm.startPrank(owner);
        factory.createPoolStandard(tokenA, tokenB);

        vm.expectRevert("PoolFactory: Pool exists");
        factory.createPoolStandard(tokenA, tokenB);
        vm.stopPrank();
    }

    function test_RevertWhen_FactoryFunctionsCalledByNonOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        factory.createPoolStandard(tokenA, tokenB);
        vm.stopPrank();
    }
}
