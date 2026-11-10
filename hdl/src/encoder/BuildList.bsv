package BuildList;

import List :: *;

//see BuildVector documentation in the standard lib

typeclass BuildList#(type t, type r) dependencies(r determines t);
    function r buildList_(List#(t) l, t x);
endtypeclass

instance BuildList#(t, List#(t));
    function List#(t) buildList_(List#(t) l, t x);
        return reverse(List::cons(x, l));
    endfunction
endinstance

instance BuildList#(t, function r f(t y))
    provisos(
        BuildList#(t, r)
    );
    function function r f(t y) buildList_(List#(t) v, t x);
        return buildList_(List::cons(x, v));
    endfunction
endinstance

function r list(t x)
    provisos(
        BuildList#(t, r)
    );
    return buildList_(Nil, x);
endfunction

endpackage