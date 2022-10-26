module aux::authority {
    use aptos_framework::account::SignerCapability;
    use aptos_framework::account;
    use std::signer;

    friend aux::clob_market;

    const E_NOT_SELF_SIGNED: u64 = 1001;
    const E_CANNOT_SIGN_FOR_OTHER: u64 = 1002;
    const E_NOT_OWNER: u64 = 1003;


    struct Authority has key {
        signer_capability: SignerCapability,
        owner_address: address,
    }
    // get signer for the module itself.
    public(friend) fun get_signer_self(): signer acquires Authority {
        assert!(
            exists<Authority>(@aux),
            E_NOT_SELF_SIGNED,
        );

        let auth = borrow_global<Authority>(@aux);

        let auth_signer = account::create_signer_with_capability(&auth.signer_capability);

        assert!(
            signer::address_of(&auth_signer) == @aux,
            E_CANNOT_SIGN_FOR_OTHER,
        );

        auth_signer
    }
}
