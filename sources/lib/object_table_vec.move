// like table vec but use dof instead
module suilette::object_table_vec {
    use sui::object_table::{Self, ObjectTable};
    use sui::tx_context::TxContext;

    struct ObjectTableVec<phantom Element: key + store> has store {
        /// The contents of the table vector.
        contents: ObjectTable<u64, Element>,
    }

    const EIndexOutOfBound: u64 = 0;
    const ETableNonEmpty: u64 = 1;

    /// Create an empty TableVec.
    public fun empty<Element: key + store>(ctx: &mut TxContext): ObjectTableVec<Element> {
        ObjectTableVec {
            contents: object_table::new(ctx)
        }
    }

    /// Return a ObjectTableVec of size one containing element `e`.
    public fun singleton<Element: key + store>(e: Element, ctx: &mut TxContext): ObjectTableVec<Element> {
        let t = empty(ctx);
        push_back(&mut t, e);
        t
    }

    /// Return the length of the ObjectTableVec.
    public fun length<Element: key + store>(t: &ObjectTableVec<Element>): u64 {
        object_table::length(&t.contents)
    }

    /// Return if the ObjectTableVec is empty or not.
    public fun is_empty<Element: key + store>(t: &ObjectTableVec<Element>): bool {
        length(t) == 0
    }

    /// Acquire an immutable reference to the `i`th element of the ObjectTableVec `t`.
    /// Aborts if `i` is out of bounds.
    public fun borrow<Element: key + store>(t: &ObjectTableVec<Element>, i: u64): &Element {
        assert!(length(t) > i, EIndexOutOfBound);
        object_table::borrow(&t.contents, i)
    }

    /// Add element `e` to the end of the ObjectTableVec `t`.
    public fun push_back<Element: key + store>(t: &mut ObjectTableVec<Element>, e: Element) {
        let key = length(t);
        object_table::add(&mut t.contents, key, e);
    }

    /// Return a mutable reference to the `i`th element in the ObjectTableVec `t`.
    /// Aborts if `i` is out of bounds.
    public fun borrow_mut<Element: key + store>(t: &mut ObjectTableVec<Element>, i: u64): &mut Element {
        assert!(length(t) > i, EIndexOutOfBound);
        object_table::borrow_mut(&mut t.contents, i)
    }

    /// Pop an element from the end of ObjectTableVec `t`.
    /// Aborts if `t` is empty.
    public fun pop_back<Element: key + store>(t: &mut ObjectTableVec<Element>): Element {
        let length = length(t);
        assert!(length > 0, EIndexOutOfBound);
        object_table::remove(&mut t.contents, length - 1)
    }

    /// Destroy the ObjectTableVec `t`.
    /// Aborts if `t` is not empty.
    public fun destroy_empty<Element: key + store>(t: ObjectTableVec<Element>) {
        assert!(length(&t) == 0, ETableNonEmpty);
        let ObjectTableVec { contents } = t;
        object_table::destroy_empty(contents);
    }
}