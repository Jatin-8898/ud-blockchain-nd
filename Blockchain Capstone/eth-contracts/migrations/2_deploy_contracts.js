// migrating the appropriate contracts
//var SquareVerifier = artifacts.require("./SquareVerifier.sol");
var SquareVerifier = artifacts.require("verifier.sol");
var SolnSquareVerifier = artifacts.require("./SolnSquareVerifier.sol");

module.exports = async function(deployer) {
  await deployer.deploy(SquareVerifier);
  //deployer.deploy(SolnSquareVerifier);
  await deployer.deploy(SolnSquareVerifier, SquareVerifier.address, "Div_ERC721MintableToken", "DIV_EC_721");
};
