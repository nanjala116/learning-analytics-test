/*
  First milestone: prerequisite-aware arithmetic learning paths.

  Run tests:
    swipl -q -s arithmetic_path.pl -g run_tests -t halt

  Try interactively:
    swipl -s arithmetic_path.pl
    ?- learning_path(division, [addition, multiplication], Path).

  Path entries are actions: review(Concept) or learn(Concept).
  This is curriculum/path logic only; it does not perform Bayesian inference.
*/

:- use_module(library(lists)).
:- use_module(library(plunit)).

% ---- Concept inventory ----
concept(counting_and_number_sense).
concept(place_value).
concept(number_types).
concept(addition).
concept(subtraction).
concept(multiplication).
concept(fractions).
concept(decimals).
concept(division).
concept(exponents).
concept(logarithms).
concept(operation_properties).

% ---- Typed educational relationships ----
% prerequisite(Prerequisite, Target).
prerequisite(counting_and_number_sense, place_value).
prerequisite(place_value, number_types).
prerequisite(number_types, addition).
prerequisite(addition, subtraction).
prerequisite(addition, multiplication).
prerequisite(subtraction, multiplication).
prerequisite(number_types, fractions).
prerequisite(fractions, decimals).
prerequisite(multiplication, division).
prerequisite(fractions, division).
prerequisite(decimals, division).
prerequisite(multiplication, exponents).
prerequisite(exponents, logarithms).
prerequisite(addition, operation_properties).
prerequisite(multiplication, operation_properties).

% Examples of non-ordering relations. These do not constrain learning order.
related_to(fractions, ratios).
suggested_link_of(division, division_practice_set).
part_of(addition, arithmetic_operations).
part_of(subtraction, arithmetic_operations).
part_of(multiplication, arithmetic_operations).
part_of(division, arithmetic_operations).

% ---- Path generation ----
% learning_path(+Target, +MasteredConcepts, -Actions)
% Collects all prerequisite ancestors of Target, adds Target, removes concepts
% already mastered, and returns a topological ordering of the remaining concepts.
% Actions mark mastered concepts as review(...) and others as learn(...).
learning_path(Target, Mastered, Actions) :-
    concept(Target),
    findall(C, required_concept(Target, C), Required0),
    sort(Required0, Required),
    include(not_mastered(Mastered), Required, Unmastered),
    topological_order(Unmastered, Ordered),
    maplist(action_for(Mastered), Ordered, Actions).

% A concept is required if it is the target itself or an ancestor prerequisite.
required_concept(Target, Target).
required_concept(Target, Ancestor) :-
    prerequisite(Ancestor, Target).
required_concept(Target, Ancestor) :-
    prerequisite(Immediate, Target),
    required_concept(Immediate, Ancestor).

not_mastered(Mastered, Concept) :-
    \+ memberchk(Concept, Mastered).

action_for(Mastered, Concept, review(Concept)) :-
    memberchk(Concept, Mastered), !.
action_for(_, Concept, learn(Concept)).

% Kahn-style topological sorting. The tie-breaker is alphabetical for stable,
% repeatable output; any valid prerequisite-respecting order is acceptable.
topological_order(Nodes, Ordered) :-
    topo_loop(Nodes, [], Ordered).

topo_loop([], _, []) :- !.
topo_loop(Remaining, Done, [Next|Rest]) :-
    select(Next, Remaining, AfterSelect),
    \+ ( prerequisite(Parent, Next),
         memberchk(Parent, Remaining),
         Parent \= Next ),
    !,
    topo_loop(AfterSelect, [Next|Done], Rest).
topo_loop(Remaining, _, _) :-
    throw(error(cyclic_or_invalid_prerequisite_graph(Remaining),
                context(topological_order/2, 'No eligible concept; check for a cycle or missing concept'))).

% ---- Next concept selector (not a learner-action policy) ----
% Select the first unmastered concept on the prerequisite path. Concrete
% learner actions are produced separately by score_policy_actions/2.
next_concept_to_learn(Target, Mastered, Concept) :-
    learning_path(Target, Mastered, Actions),
    member(learn(Concept), Actions), !.
next_concept_to_learn(Target, Mastered, target_already_mastered(Target)) :-
    learning_path(Target, Mastered, []).

% ---- Tests ----
:- begin_tests(arithmetic_path).

test(all_required_prerequisites_are_included, [nondet]) :-
    learning_path(division, [], Path),
    assertion(Path == [
        learn(counting_and_number_sense),
        learn(place_value),
        learn(number_types),
        learn(addition),
        learn(fractions),
        learn(decimals),
        learn(subtraction),
        learn(multiplication),
        learn(division)
    ]).

test(skips_mastered_concepts_and_keeps_required_order, [nondet]) :-
    learning_path(division, [addition, multiplication], Path),
    assertion(memberchk(learn(counting_and_number_sense), Path)),
    assertion(memberchk(learn(place_value), Path)),
    assertion(memberchk(learn(number_types), Path)),
    assertion(memberchk(learn(fractions), Path)),
    assertion(memberchk(learn(decimals), Path)),
    assertion(memberchk(learn(subtraction), Path)),
    assertion(memberchk(learn(division), Path)),
    assertion(\+ memberchk(learn(addition), Path)),
    assertion(\+ memberchk(learn(multiplication), Path)),
    precedes(Path, learn(fractions), learn(division)),
    precedes(Path, learn(decimals), learn(division)).

precedes(List, A, B) :-
    nth0(IndexA, List, A),
    nth0(IndexB, List, B),
    IndexA < IndexB.

test(first_unmastered_concept_is_selected) :-
    next_concept_to_learn(division, [counting_and_number_sense, place_value, number_types],
                         addition).

test(target_already_mastered_is_not_a_retest_action) :-
    next_concept_to_learn(division,
        [counting_and_number_sense, place_value, number_types, addition,
         fractions, decimals, subtraction, multiplication, division],
        target_already_mastered(division)).

test(non_prerequisite_relations_do_not_affect_path, [nondet]) :-
    learning_path(division, [], Path),
    assertion(\+ member(learn(ratios), Path)),
    assertion(\+ member(learn(division_practice_set), Path)).

:- end_tests(arithmetic_path).
