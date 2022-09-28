module tortuga::stake_router{
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use tortuga::staked_aptos_coin::StakedAptosCoin;

    public entry fun stake(_user: &signer, _amount: u64){
    }

    public entry fun unstake(_user: &signer, _amount: u64){
    }
    // use this on tortuga frontend at 2022-9-26
    public entry fun unstake_immediate(_user: &signer, _amount: u64){
    }

    public fun stake_coins(aptos: coin::Coin<AptosCoin>): coin::Coin<StakedAptosCoin>{
        coin::destroy_zero(aptos);
        coin::zero<StakedAptosCoin>()
    }
}