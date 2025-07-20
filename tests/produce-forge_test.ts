import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Ensure that produce investment can be created by authorized manager",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const investor = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            // Add deployer as produce manager
            Tx.contractCall('produce-forge', 'add-produce-manager', [types.principal(deployer.address)], deployer.address),
            
            // Create produce investment
            Tx.contractCall('produce-forge', 'create-produce-investment', [
                types.uint(1000000),
                types.ascii('wheat'),
                types.ascii('Nebraska'),
                types.uint(10000)
            ], deployer.address)
        ]);

        // Verify investment creation
        assertEquals(block.receipts.length, 2);
        block.receipts[1].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Verify investor can invest in produce opportunity",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const investor = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            // Setup: Add manager and create investment
            Tx.contractCall('produce-forge', 'add-produce-manager', [types.principal(deployer.address)], deployer.address),
            Tx.contractCall('produce-forge', 'create-produce-investment', [
                types.uint(1000000),
                types.ascii('wheat'),
                types.ascii('Nebraska'),
                types.uint(10000)
            ], deployer.address),

            // Investor invests
            Tx.contractCall('produce-forge', 'invest-in-produce', [
                types.uint(1),
                types.uint(50000)
            ], investor.address)
        ]);

        // Verify investment
        assertEquals(block.receipts.length, 3);
        block.receipts[2].result.expectOk().expectUint(50000);
    }
});

Clarinet.test({
    name: "Prevent unauthorized produce investment creation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const investor = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            // Attempt to create investment without authorization
            Tx.contractCall('produce-forge', 'create-produce-investment', [
                types.uint(1000000),
                types.ascii('wheat'),
                types.ascii('Nebraska'),
                types.uint(10000)
            ], investor.address)
        ]);

        // Verify unauthorized attempt fails
        block.receipts[0].result.expectErr().expectUint(100);
    }
});