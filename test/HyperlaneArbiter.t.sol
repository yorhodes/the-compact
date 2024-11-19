import "./TheCompact.t.sol";

import {MockMailbox} from "hyperlane/contracts/mock/MockMailbox.sol";
import {TypeCasts} from "hyperlane/contracts/libs/TypeCasts.sol";

import "../src/HyperlaneArbiter.sol";

contract HyperlaneArbiterTest is TheCompactTest {
    using TypeCasts for address;

    uint32 origin = 1;
    uint32 destination = 2;

    MockMailbox originMailbox;
    MockMailbox destinationMailbox;

    HyperlaneArbiter originArbiter;
    HyperlaneArbiter destinationArbiter;

    function setUp() public override {
        super.setUp();

        originMailbox = new MockMailbox(origin);
        destinationMailbox = new MockMailbox(destination);

        originMailbox.addRemoteMailbox(destination, destinationMailbox);
        destinationMailbox.addRemoteMailbox(origin, originMailbox);

        originArbiter = new HyperlaneArbiter(address(originMailbox), address(theCompact));
        destinationArbiter = new HyperlaneArbiter(address(destinationMailbox), address(0));

        originArbiter.enrollRemoteRouter(destination, address(destinationArbiter).addressToBytes32());
        destinationArbiter.enrollRemoteRouter(origin, address(originArbiter).addressToBytes32());
    }

    function test_claimWithWitness() public override {
        ResetPeriod resetPeriod = ResetPeriod.TenMinutes;
        Scope scope = Scope.Multichain;
        uint256 amount = 1e18;
        uint256 nonce = 0;
        uint256 expires = block.timestamp + 1000;
        address claimant = 0x1111111111111111111111111111111111111111;
        address arbiter = address(originArbiter);

        vm.prank(allocator);
        theCompact.__registerAllocator(allocator, "");

        vm.prank(swapper);
        uint256 id = theCompact.deposit{ value: amount }(allocator, resetPeriod, scope, swapper);
        assertEq(theCompact.balanceOf(swapper, id), amount);

        uint256 fee = amount - 1;
        uint32 chainId = destination;

        string memory witnessTypestring = "Intent intent)Intent(uint32 chainId,address recipient,address token,uint256 amount)";

        Intent memory intent = Intent(fee, chainId, address(token), swapper, amount);

        vm.chainId(destination);

        token.mint(claimant, amount);

        vm.startPrank(claimant);
        // TODO: permit2 approvals
        token.approve(address(destinationArbiter), amount);
        destinationArbiter.fill(origin, intent);
        vm.stopPrank();

        originMailbox.processNextInboundMessage();

        bytes32 witness = originArbiter.hash(intent);

        bytes32 claimHash = keccak256(
            abi.encode(
                keccak256("Compact(address arbiter,address sponsor,uint256 nonce,uint256 expires,uint256 id,uint256 amount,Intent intent)Intent(uint32 chainId,address recipient,address token,uint256 amount)"),
                arbiter,
                swapper,
                nonce,
                expires,
                id,
                amount,
                witness
            )
        );

        bytes32 digest = keccak256(abi.encodePacked(bytes2(0x1901), theCompact.DOMAIN_SEPARATOR(), claimHash));

        (bytes32 r, bytes32 vs) = vm.signCompact(swapperPrivateKey, digest);
        bytes memory sponsorSignature = abi.encodePacked(r, vs);

        (r, vs) = vm.signCompact(allocatorPrivateKey, digest);
        bytes memory allocatorSignature = abi.encodePacked(r, vs);

        ClaimWithWitness memory claim = ClaimWithWitness(allocatorSignature, sponsorSignature, swapper, nonce, expires, witness, witnessTypestring, id, amount, claimant, fee);

        originArbiter.claim(claim);

        assertEq(address(theCompact).balance, amount);
        assertEq(claimant.balance, 0);

        assertEq(theCompact.balanceOf(swapper, id), amount - fee);
        assertEq(theCompact.balanceOf(claimant, id), fee);
    }
}
