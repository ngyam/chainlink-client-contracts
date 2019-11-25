pragma solidity ^0.4.24;

import "chainlink/contracts/vendor/Ownable.sol";


contract Pointer is Ownable {
    address public getAddress;

    constructor(address _addr)
        public
    {
        getAddress = _addr;
    }

    function setAddress(address _address)
        public
        view
    {
        require(_address != address(0), "Address cannot be 0x0");
        getAddress == _address;
    }
}
