module aux::critbit {
    use aptos_std::table_with_length::{Self as table, TableWithLength as Table};
    const E_EMPTY_TREE: u64 = 2;

    // NULL_INDEX is 1 << 63;
    const NULL_INDEX: u64 = 1 << 63;  // 9223372036854775808
    struct TreeNode has store, copy, drop {
        // mask
        mask: u128,
        // parent
        parent: u64,
        // left child
        left_child: u64,
        // right child.
        right_child: u64,
    }

    struct DataNode<V> has store, copy, drop {
        // mask
        key: u128,
        // parent
        parent: u64,
        value: V,
    }

    struct CritbitTree<phantom V> has store {
        root: u64,
        tree: Table<u64, TreeNode>,
        min_index: u64,
        max_index: u64,
        entries: Table<u64, DataNode<V>>,
    }

    /// size returns the number of elements in the CritbitTree.
    public fun size<V>(tree: &CritbitTree<V>): u64 {
        table::length(&tree.entries)
    }
    /// get index of the max of the tree.
    public fun get_max_index<V>(tree: &CritbitTree<V>): u64 {
        let current = tree.max_index;
        assert!(current != NULL_INDEX, E_EMPTY_TREE);
        current
    }
    /// borrow returns a reference to the element with its key at the given index
    public fun borrow_at_index<V>(tree: &CritbitTree<V>, index: u64): (u128, &V) {
        let entry = table::borrow(&tree.entries, index);
        (entry.key, &entry.value)
    }
    /// get index of the min of the tree.
    public fun get_min_index<V>(tree: &CritbitTree<V>): u64 {
        let current = tree.min_index;
        assert!(current != NULL_INDEX, E_EMPTY_TREE);
        current
    }
    /// empty returns true if the CritbitTree is empty.
    public fun empty<V>(tree: &CritbitTree<V>): bool {
        table::length(&tree.entries) == 0
    }
    /// borrow_mut returns a mutable reference to the element with its key at the given index
    public fun borrow_at_index_mut<V>(tree: &mut CritbitTree<V>, index: u64): (u128, &mut V) {
        let entry = table::borrow_mut(&mut tree.entries, index);
        (entry.key, &mut entry.value)
    }
}
