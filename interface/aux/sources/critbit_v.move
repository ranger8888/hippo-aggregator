module aux::critbit_v {

    use std::vector;
    use std::vector::{swap, pop_back};

    const E_INVALID_ARGUMENT: u64 = 1;
    const E_EMPTY_TREE: u64 = 2;
    const E_TREE_NOT_EMPTY: u64 = 3;
    const E_KEY_ALREADY_EXIST: u64 = 4;
    const E_INDEX_OUT_OF_RANGE: u64 = 5;
    const E_DATA_NODE_LACK_PARENT: u64 = 6;
    const E_CANNOT_DESTRORY_NON_EMPTY: u64 = 7;
    const E_EXCEED_CAPACITY: u64 = 8;
    // NULL_INDEX is 1 << 63;
    const NULL_INDEX: u64 = 1 << 63;  // 9223372036854775808

    struct DataNode<V> has store, copy, drop {
        // mask
        key: u128,
        // parent
        parent: u64,
        value: V,
    }

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
    struct CritbitTree<V> has store, copy, drop {
        root: u64,
        tree: vector<TreeNode>,
        min_index: u64,
        max_index: u64,
        entries: vector<DataNode<V>>,
    }
    /// get index of the min of the tree.
    public fun get_min_index<V>(tree: &CritbitTree<V>): u64 {
        let current = tree.min_index;
        assert!(current != NULL_INDEX, E_EMPTY_TREE);
        current
    }
    /// borrow returns a reference to the element with its key at the given index
    public fun borrow_at_index<V>(tree: &CritbitTree<V>, index: u64): (u128, &V) {
        let entry = vector::borrow(&tree.entries, index);
        (entry.key, &entry.value)
    }
    /// remove deletes and returns the element from the CritbitTree.
    public fun remove<V>(tree: &mut CritbitTree<V>, index: u64): (u128, V) {
        let old_length = vector::length(&tree.entries);
        assert!(old_length > index, E_INDEX_OUT_OF_RANGE);

        if (tree.min_index == index) {
            tree.min_index = next_in_order(tree, index);
        };
        if (tree.max_index == index) {
            tree.max_index = next_in_reverse_order(tree, index);
        };

        let data_index_converted = convert_data_index(index);

        let original_parent = vector::borrow(&tree.entries, index).parent;
        let is_left_child = if (original_parent != NULL_INDEX) {
            is_left_child(tree, data_index_converted, original_parent)
        } else {
            false
        };

        let end_index = old_length - 1;
        if (end_index != index) {
            let end_parent = vector::borrow(&tree.entries, end_index).parent;
            let is_end_index_left = is_left_child(tree, convert_data_index(end_index), end_parent);
            swap(&mut tree.entries, index, end_index);
            if (is_end_index_left) {
                replace_left_child(tree, end_parent, data_index_converted);
            } else {
                replace_right_child(tree, end_parent, data_index_converted);
            };
            if (is_left_child) {
                replace_left_child(tree, original_parent, convert_data_index(end_index));
            } else {
                replace_right_child(tree, original_parent, convert_data_index(end_index));
            };
            if (tree.max_index == end_index) {
                tree.max_index = index;
            };
            if (tree.min_index == end_index) {
                tree.min_index = index;
            }
        };

        let DataNode<V> {key, value, parent: _} = pop_back(&mut tree.entries);

        if (vector::length(&tree.entries) == 0) {
            assert!(original_parent == NULL_INDEX, E_TREE_NOT_EMPTY);
            assert!(vector::length(&tree.tree) == 0, E_TREE_NOT_EMPTY);
            tree.root = NULL_INDEX;
            tree.min_index = NULL_INDEX;
            tree.max_index = NULL_INDEX;
            (key, value)
        } else {
            assert!(original_parent != NULL_INDEX, E_DATA_NODE_LACK_PARENT);
            let original_parent_node = vector::borrow(&tree.tree, original_parent);
            let other_child = if (is_left_child) {
                original_parent_node.right_child
            } else {
                original_parent_node.left_child
            };
            let grand_parent = original_parent_node.parent;
            if (grand_parent == NULL_INDEX) {
                replace_parent(tree, other_child, NULL_INDEX);
                tree.root = other_child;
            } else {
                replace_child(tree, grand_parent, original_parent, other_child);
            };

            let tree_size = vector::length(&tree.tree);
            assert!(tree_size > original_parent, E_INDEX_OUT_OF_RANGE);
            let tree_end_index = tree_size - 1;
            if (tree_end_index != original_parent) {
                swap(&mut tree.tree, tree_end_index, original_parent);
                let switched_node = vector::borrow(&tree.tree, original_parent);
                let left_child = switched_node.left_child;
                let right_child = switched_node.right_child;
                let new_parent = switched_node.parent;
                if (switched_node.parent != NULL_INDEX) {
                    replace_child(tree, new_parent, tree_end_index, original_parent);
                };
                replace_left_child(tree, original_parent, left_child);
                replace_right_child(tree, original_parent, right_child);
                if (tree.root == tree_end_index) {
                    tree.root = original_parent;
                };
            };
            pop_back(&mut tree.tree);
            (key, value)
        }
    }
    fun convert_data_index(index: u64): u64 {
        MAX_U64 - index
    }
    /// find next value in order (the key is increasing)
    public fun next_in_order<V>(tree: &CritbitTree<V>, index: u64): u64 {
        let current = convert_data_index(index);
        let parent = vector::borrow(&tree.entries, index).parent;
        if (parent == NULL_INDEX) {
            NULL_INDEX
        } else {
            while(parent != NULL_INDEX && is_right_child(tree, current, parent)) {
                current = parent;
                parent = vector::borrow(&tree.tree, current).parent;
            };

            if (parent == NULL_INDEX) {
                NULL_INDEX
            } else {
                get_min_index_from(tree, vector::borrow(&tree.tree, parent).right_child)
            }
        }
    }
    /// find next value in reverse order (the key is decreasing)
    public fun next_in_reverse_order<V>(tree: &CritbitTree<V>, index: u64): u64 {
        let current = convert_data_index(index);
        let parent = vector::borrow(&tree.entries, index).parent;
        if (parent == NULL_INDEX) {
            NULL_INDEX
        } else {
            while (parent != NULL_INDEX && is_left_child(tree, current, parent)) {
                current = parent;
                parent = vector::borrow(&tree.tree, current).parent;
            };

            if (parent == NULL_INDEX) {
                NULL_INDEX
            } else {
                get_max_index_from(tree, vector::borrow(&tree.tree, parent).left_child)
            }
        }
    }
    fun is_right_child<V>(tree: &CritbitTree<V>, index: u64, parent_index: u64): bool {
        vector::borrow(&tree.tree, parent_index).right_child == index
    }

    fun is_left_child<V>(tree: &CritbitTree<V>, index: u64, parent_index: u64): bool {
        vector::borrow(&tree.tree, parent_index).left_child == index
    }

    fun replace_left_child<V>(tree: &mut CritbitTree<V>, parent_index: u64, new_child: u64) {
        if (parent_index == NULL_INDEX) {
            return
        };
        vector::borrow_mut(&mut tree.tree, parent_index).left_child = new_child;
        if (new_child != NULL_INDEX) {
            if (is_data_index(new_child)) {
                vector::borrow_mut(&mut tree.entries, convert_data_index(new_child)).parent = parent_index;
            } else {
                vector::borrow_mut(&mut tree.tree, new_child).parent = parent_index;
            };
        };
    }

    fun replace_right_child<V>(tree: &mut CritbitTree<V>, parent_index: u64, new_child: u64) {
        if (parent_index == NULL_INDEX) {
            return
        };
        vector::borrow_mut(&mut tree.tree, parent_index).right_child = new_child;
        if (new_child != NULL_INDEX) {
            if (is_data_index(new_child)) {
                vector::borrow_mut(&mut tree.entries, convert_data_index(new_child)).parent = parent_index;
            } else {
                vector::borrow_mut(&mut tree.tree, new_child).parent = parent_index;
            };
        };
    }
    fun replace_parent<V>(tree: &mut CritbitTree<V>, child: u64, new_parent: u64) {
        if (is_data_index(child)) {
            vector::borrow_mut(&mut tree.entries, convert_data_index(child)).parent = new_parent;
        } else {
            vector::borrow_mut(&mut tree.tree, child).parent = new_parent;
        }
    }
    /// Replace the child of parent if parent_index is not NULL_INDEX.
    fun replace_child<V>(tree: &mut CritbitTree<V>, parent_index: u64, original_child: u64, new_child: u64) {
        if (parent_index != NULL_INDEX) {
            if (is_right_child(tree, original_child, parent_index)) {
                replace_right_child(tree, parent_index, new_child);
            } else if (is_left_child(tree, original_child, parent_index)) {
                replace_left_child(tree, parent_index, new_child);
            }
        }
    }
    fun is_data_index(index: u64): bool {
        index > NULL_INDEX
    }
}
