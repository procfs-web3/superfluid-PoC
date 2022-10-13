// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


struct Context {
    //
    // Call context
    //
    // callback level
    uint8 appLevel;
    // type of call
    uint8 callType;
    // the system timestamp
    uint256 timestamp;
    // The intended message sender for the call
    address msgSender;

    //
    // Callback context
    //
    // For callbacks it is used to know which agreement function selector is called
    bytes4 agreementSelector;
    // User provided data for app callbacks
    bytes userData;

    //
    // App context
    //
    // app allowance granted
    uint256 appAllowanceGranted;
    // app allowance wanted by the app callback
    uint256 appAllowanceWanted;
    // app allowance used, allowing negative values over a callback session
    int256 appAllowanceUsed;
    // app address
    address appAddress;
    // app allowance in super token
    ISuperfluidToken appAllowanceToken;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint256);
    function transfer(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external;
}

interface ISuperfluidToken is IERC20 {
    function realtimeBalanceOf(address account, uint256 timestamp) external view returns (int256, uint256, uint256);
    function getAgreementData(address agreementClass, bytes32 id, uint dataLength) external view returns(bytes32[] memory);
}

interface ISuperToken is ISuperfluidToken {
    function getUnderlyingToken() external view returns (address);
    function upgrade(uint256 amount) external;
    function downgrade(uint256 amount) external;
}

interface ISuperAgreement {

}

interface ISuperApp {
    function afterAgreementTerminated(
        ISuperToken _superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata cbdata,
        bytes calldata ctx
    )  external returns (bytes memory);
    function distribute() external;
    function getLastDistributionAt() external view returns (uint256);
    function getOutputRate() external view returns (uint256);
}

interface ISuperfluid {
    function callAppAction(ISuperApp app, bytes memory callData) external returns (bytes memory returnedData);
    function callAgreement(ISuperAgreement agreementClass, bytes calldata callData, bytes calldata userData) external returns (bytes memory returnedData);
    function getAgreementClass(bytes32 agreementType) external view returns(ISuperAgreement);
    function callAgreementWithContext(ISuperAgreement agreementClass, bytes calldata callData, bytes calldata userData, bytes calldata ctx) external returns (bytes memory newCtx, bytes memory returnedData);
    function isCtxValid(bytes calldata ctx) external view returns (bool);
    function decodeCtx(bytes memory ctx) external pure returns (Context memory);
}

interface ICFA is ISuperAgreement {
    function createFlow(ISuperfluidToken token, address receiver, int96 flowRate, bytes calldata ctx) external returns(bytes memory);
    function deleteFlow(ISuperfluidToken token, address sender, address receiver,  bytes calldata ctx) external returns(bytes memory);
    function getFlow(ISuperfluidToken token, address sender, address receiver) external view returns (uint256 timestamp, int96 flowRate, uint256 deposit, uint256 owedDeposit);
    function getMaximumFlowRateFromDeposit(ISuperfluidToken token, uint256 deposit) external view returns (int96 flowRate);
}

interface IIDA is ISuperAgreement {
    function createIndex(ISuperToken token, uint32 indexId, bytes calldata ctx) external returns(bytes memory newCtx);
    function getIndex(ISuperToken token, address publisher, uint32 indexId) external view returns(bool exist, uint128 indexValue, uint128 totalUnitsApproved, uint128 totalUnitsPending);
    function getSubscription(ISuperfluidToken token, address publisher, uint32 indexId, address subscriber) external view returns (bool, bool, uint128, uint256);
    function updateIndex(ISuperToken token, uint32 indexId, uint128 indexValue, bytes calldata ctx) external returns(bytes memory newCtx);
    function updateSubscription(ISuperToken token, uint32 indexId, address subscriber, uint128 units, bytes calldata ctx) external returns (bytes memory newCtx);
    function revokeSubscription(ISuperfluidToken token, address publisher, uint32 indexId, bytes calldata ctx) external returns (bytes memory newCtx);
    function approveSubscription(ISuperfluidToken token, address publisher, uint32 indexId,  bytes calldata ctx) external returns(bytes memory newCtx);
    function claim(ISuperToken token, address publisher, uint32 indexId, address subscriber, bytes calldata ctx) external returns(bytes memory newCtx);
    function listSubscriptions(ISuperfluidToken token, address subscriber) external view returns(address[] memory publishers, uint32[] memory indexIds, uint128[] memory unitsList);
}

interface ISwapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface ISwapPair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface WMATIC is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface MATICx is ISuperToken {
    function upgradeByETH() external payable;
    function downgradeToETH(uint256 amount) external;
}

interface IReceiverMaster {
    function superfluid() external view returns (ISuperfluid);
    function cfa() external view returns (ICFA);
    function receiver() external view returns (Receiver);
    function maticx() external view returns (MATICx);
    function usdcx() external view returns (ISuperToken);
    function qix() external view returns (ISuperToken);
    function wmatic() external view returns (WMATIC);
    function usdc() external view returns (IERC20);
    function qi() external view returns (IERC20);
    function miva() external view returns (ISuperToken);
    function usdcPool() external view returns (ISwapPair); // WMATIC-USDC pool
    function mivaPool() external view returns (ISwapPair); // WMATIC-MIVA pool
    function qiPool() external view returns (ISwapPair);
}

interface IStreamExchange {
    function getOwner() external view returns (address);
    function getInputToken() external view returns (ISuperToken);
    function getOuputToken() external view returns (ISuperToken);
}

contract Receiver {

    IReceiverMaster master;
    MATICx maticx;
    ISuperToken usdcx;
    ISuperToken qix;
    WMATIC wmatic;
    IERC20 usdc;
    IERC20 qi;
    ISwapPair usdcPool;
    ISwapPair qiPool;

    constructor(address _master) {
        master = IReceiverMaster(_master);
        maticx = master.maticx();
        usdcx = master.usdcx();
        qix = master.qix();
        wmatic = master.wmatic();
        usdc = master.usdc();
        qi = master.qi();
        usdcPool = master.usdcPool();
        qiPool = master.qiPool();
    }

    function redeem() public {
        uint256 amountIn;
        uint256 amountOut;
        uint112 reserveIn;
        uint112 reserveOut;

        maticx.downgradeToETH(maticx.balanceOf(address(this)) * 9999/10000);
            
        usdcx.downgrade(usdcx.balanceOf(address(this))* 9999/10000);
        amountIn = usdc.balanceOf(address(this));
        usdc.transfer(address(usdcPool), amountIn);
        (reserveOut, reserveIn, ) = usdcPool.getReserves();
        usdcPool.swap(SwapUtils.getAmountOut(amountIn, reserveIn, reserveOut), 0, address(this), "");

    
        qix.downgrade(qix.balanceOf(address(this))* 9999/10000);
        amountIn = qi.balanceOf(address(this));
        amountIn = qi.balanceOf(address(this));
        qi.transfer(address(qiPool), amountIn);
        (reserveOut, reserveIn, ) = qiPool.getReserves();
        qiPool.swap(SwapUtils.getAmountOut(amountIn, reserveIn, reserveOut), 0, address(this), "");
    
        // withdraw wmatic
        wmatic.withdraw(wmatic.balanceOf(address(this)));

        payable(address(master)).transfer(address(this).balance);
    }

    receive () external payable {

    }
}

library ContextDefinitions {

    /**************************************************************************
    / Call info
    /**************************************************************************/

    // app level
    uint256 constant internal CALL_INFO_APP_LEVEL_MASK = 0xFF;

    // call type
    uint256 constant internal CALL_INFO_CALL_TYPE_SHIFT = 32;
    uint256 constant internal CALL_INFO_CALL_TYPE_MASK = 0xF << CALL_INFO_CALL_TYPE_SHIFT;
    uint8 constant internal CALL_INFO_CALL_TYPE_AGREEMENT = 1;
    uint8 constant internal CALL_INFO_CALL_TYPE_APP_ACTION = 2;
    uint8 constant internal CALL_INFO_CALL_TYPE_APP_CALLBACK = 3;

    function decodeCallInfo(uint256 callInfo)
        internal pure
        returns (uint8 appCallbackLevel, uint8 callType)
    {
        appCallbackLevel = uint8(callInfo & CALL_INFO_APP_LEVEL_MASK);
        callType = uint8((callInfo & CALL_INFO_CALL_TYPE_MASK) >> CALL_INFO_CALL_TYPE_SHIFT);
    }

    function encodeCallInfo(uint8 appCallbackLevel, uint8 callType)
        internal pure
        returns (uint256 callInfo)
    {
        return uint256(appCallbackLevel) | (uint256(callType) << CALL_INFO_CALL_TYPE_SHIFT);
    }

    function serializeContext(Context memory context) internal pure returns (bytes memory ctx)
    {
        uint256 callInfo = ContextDefinitions.encodeCallInfo(context.appLevel, context.callType);
        uint256 allowanceIO =
            uint128(context.appAllowanceGranted) |
            (uint256(uint128(context.appAllowanceWanted) << 128));
        // NOTE: nested encoding done due to stack too deep error when decoding in _decodeCtx
        ctx = abi.encode(
            abi.encode(
                callInfo,
                context.timestamp,
                context.msgSender,
                context.agreementSelector,
                context.userData
            ),
            abi.encode(
                allowanceIO,
                context.appAllowanceUsed,
                context.appAddress,
                context.appAllowanceToken
            )
        );
    }

    function unserializeContext(bytes memory ctx) internal pure returns (Context memory context) {
        bytes memory ctx1;
        bytes memory ctx2;
        (ctx1, ctx2) = abi.decode(ctx, (bytes, bytes));
        {
            uint256 callInfo;
            (
                callInfo,
                context.timestamp,
                context.msgSender,
                context.agreementSelector,
                context.userData
            ) = abi.decode(ctx1, (
                uint256,
                uint256,
                address,
                bytes4,
                bytes));
            (context.appLevel, context.callType) = ContextDefinitions.decodeCallInfo(callInfo);
        }
        {
            uint256 allowanceIO;
            (
                allowanceIO,
                context.appAllowanceUsed,
                context.appAddress,
                context.appAllowanceToken
            ) = abi.decode(ctx2, (
                uint256,
                int256,
                address,
                ISuperfluidToken));
            context.appAllowanceGranted = allowanceIO & type(uint128).max;
            context.appAllowanceWanted = allowanceIO >> 128;
        }
    }
}

library SwapUtils {
     function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}

library IDAUtils {

    struct IndexData {
        uint128 indexValue;
        uint128 totalUnitsApproved;
        uint128 totalUnitsPending;
    }

    /// @dev Agreement data for the subscription
    struct SubscriptionData {
        uint32 subId;
        address publisher;
        uint32 indexId;
        uint128 indexValue;
        uint128 units;
    }

    function _getPublisherId(
        address publisher,
        uint32 indexId
    )
        private pure
        returns (bytes32 iId)
    {
        return keccak256(abi.encodePacked("publisher", publisher, indexId));
    }

    function _getSubscriptionId(
        address subscriber,
        bytes32 iId
    )
        private pure
        returns (bytes32 sId)
    {
        return keccak256(abi.encodePacked("subscription", subscriber, iId));
    }

    function _getIndexData(
        ISuperfluidToken token,
        bytes32 iId
    )
        private view
        returns (bool exist, IndexData memory idata)
    {
        bytes32[] memory adata = token.getAgreementData(address(this), iId, 2);
        uint256 a = uint256(adata[0]);
        uint256 b = uint256(adata[1]);
        exist = a > 0;
        if (exist) {
            // NOTE We will do an unsafe downcast from uint256 => uint128
            // as we know this is safe
            // see https://gist.github.com/0xdavinchee/9834dc689543f19ec07872ad7d766b09
            idata.indexValue = uint128(a);
            idata.totalUnitsApproved = uint128(b);
            idata.totalUnitsPending = uint128(b >> 128);
        }
    }

    function _getSubscriptionData(
        ISuperfluidToken token,
        bytes32 sId
    )
        private view
        returns (bool exist, SubscriptionData memory sdata)
    {
        bytes32[] memory adata = token.getAgreementData(address(this), sId, 2);
        uint256 a = uint256(adata[0]);
        uint256 b = uint256(adata[1]);
        exist = a > 0;
        if (exist) {
            sdata.publisher = address(uint160(a >> (12*8)));
            sdata.indexId = uint32((a >> 32) & type(uint32).max);
            sdata.subId = uint32(a & type(uint32).max);
            // NOTE We will do an unsafe downcast from uint256 => uint128
            // as we know this is safe
            // see https://gist.github.com/0xdavinchee/9834dc689543f19ec07872ad7d766b09
            sdata.indexValue = uint128(b);
            sdata.units = uint128(b >> 128);
        }
    }

    function _loadAllData(
        ISuperfluidToken token,
        address publisher,
        address subscriber,
        uint32 indexId,
        bool requireSubscriptionExisting
    )
        internal view
        returns (
            bytes32 iId,
            bytes32 sId,
            IndexData memory idata,
            bool subscriptionExists,
            SubscriptionData memory sdata
        )
    {
        bool indexExists;
        iId = _getPublisherId(publisher, indexId);
        sId = _getSubscriptionId(subscriber, iId);
        (indexExists, idata) = _getIndexData(token, iId);
        require(indexExists, "IDA: E_NO_INDEX");
        (subscriptionExists, sdata) = _getSubscriptionData(token, sId);
        if (requireSubscriptionExisting) {
            require(subscriptionExists, "IDA: E_NO_SUBS");
             // sanity check
            assert(sdata.publisher == publisher);
            assert(sdata.indexId == indexId);
        }
    }
}