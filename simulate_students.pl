/*
  Synthetic learner and quiz-data generator for the arithmetic prototype.

  Run tests:
    swipl -q -s simulate_students.pl -g run_tests -t halt

  Generate CSV:
  swipl -q -s simulate_students.pl -g "write_synthetic_csv('synthetic_students.csv',20),halt"

  Ratings and demographic values are synthetic. hidden_mastery is ground truth
  for later evaluation and must not be supplied to the estimator.
*/

:- use_module(library(random)).
:- use_module(library(lists)).
:- use_module(library(plunit)).
:- ensure_loaded(arithmetic_path).

% Provisional synthetic mastery generation assumptions.
mastery_probability([], 0.70).
mastery_probability(Parents, Probability) :-
    Parents \= [],
    (   forall(member(Parent, Parents), sim_mastered(Parent))
    ->  Probability = 0.82
    ;   Probability = 0.12
    ).

:- thread_local sim_mastered/1.

sample_mastery(Concepts, Mastered) :-
    retractall(sim_mastered(_)),
    topological_order(Concepts, Ordered),
    sample_concepts(Ordered, Mastered),
    retractall(sim_mastered(_)).

sample_concepts([], []).
sample_concepts([Concept|Rest], Mastered) :-
    findall(Parent, prerequisite(Parent, Concept), Parents),
    mastery_probability(Parents, Probability),
    maybe_true(Probability, IsMastered),
    (   IsMastered == true
    ->  assertz(sim_mastered(Concept)), Mastered = [Concept|Tail]
    ;   Mastered = Tail
    ),
    sample_concepts(Rest, Tail).

maybe_true(Probability, true) :-
    Value is random_float,
    Value < Probability, !.
maybe_true(_, false).

% Synthetic pre-course survey profile. The familiarity scale is per concept.
random_profile(Age, Education, Goal, PriorExperience, StudyHours) :-
    random_member(Age, [7, 8, 10, 12, 16, 18, 25, 40]),
    random_member(Education, [grade_1_entry, elementary, secondary, postsecondary]),
    random_member(Goal, [division, fractions, decimals, exponents]),
    random_member(PriorExperience, [none, some, substantial]),
    random_member(StudyHours, [1, 2, 4, 6, 8]).

concept_familiarity(Concept, Rating) :-
    concept(Concept),
    random_member(Rating, [unfamiliar, vaguely_familiar, familiar, confident, not_sure]).

% Match the estimator's provisional response-likelihood assumptions.
response_probability(true, 0.80).
response_probability(false, 0.45).

sample_score(Concept, Mastered, NumberOfItems, Correct, Total) :-
    memberchk(Concept, Mastered), !,
    response_probability(true, Probability),
    sample_correct(NumberOfItems, Probability, Correct),
    Total = NumberOfItems.
sample_score(_, _, NumberOfItems, Correct, Total) :-
    response_probability(false, Probability),
    sample_correct(NumberOfItems, Probability, Correct),
    Total = NumberOfItems.

sample_correct(0, _, 0) :- !.
sample_correct(N, Probability, Correct) :-
    N > 0,
    maybe_true(Probability, Answer),
    N1 is N - 1,
    sample_correct(N1, Probability, RestCorrect),
    (Answer == true -> Correct is RestCorrect + 1 ; Correct = RestCorrect).

% Generate one record per learner and concept, including that concept's own
% survey rating and score. Profile variables are generated independently as
% synthetic descriptors; they are not currently causal in mastery simulation.
generate_learners(Count, ItemsPerConcept, Records) :-
    integer(Count), Count >= 0,
    integer(ItemsPerConcept), ItemsPerConcept > 0,
    findall(Concept, concept(Concept), Concepts),
    generate_learner_records(1, Count, Concepts, ItemsPerConcept, Records).

generate_learner_records(Current, Count, _, _, []) :- Current > Count, !.
generate_learner_records(Current, Count, Concepts, ItemsPerConcept, Records) :-
    random_profile(Age, Education, Goal, Experience, Hours),
    sample_mastery(Concepts, Mastered),
    maplist(concept_record(Current, Age, Education, Goal, Experience, Hours,
                           Mastered, ItemsPerConcept), Concepts, CurrentRecords),
    Next is Current + 1,
    generate_learner_records(Next, Count, Concepts, ItemsPerConcept, Remaining),
    append(CurrentRecords, Remaining, Records).

concept_record(Id, Age, Education, Goal, Experience, Hours, Mastered, Items,
               Concept, record(Id, Age, Education, Goal, Experience, Hours,
                               Concept, Rating, HiddenMastery, Correct, Total)) :-
    concept_familiarity(Concept, Rating),
    (memberchk(Concept, Mastered) -> HiddenMastery = true ; HiddenMastery = false),
    sample_score(Concept, Mastered, Items, Correct, Total).

write_synthetic_csv(File, LearnerCount) :-
    generate_learners(LearnerCount, 3, Records),
    setup_call_cleanup(
        open(File, write, Stream),
        ( write(Stream, 'student_id,age_years,education_level,learning_goal,prior_math_exposure,weekly_study_hours,concept,self_reported_familiarity,hidden_mastery,correct_answers,total_items\n'),
          forall(member(Record, Records), write_record(Stream, Record))
        ),
        close(Stream)).

write_record(Stream, record(Id, Age, Education, Goal, Experience, Hours,
                            Concept, Rating, Mastery, Correct, Total)) :-
    format(Stream, '~d,~d,~w,~w,~w,~d,~w,~w,~w,~d,~d~n',
           [Id, Age, Education, Goal, Experience, Hours, Concept, Rating,
            Mastery, Correct, Total]).

:- begin_tests(synthetic_students).

test(generates_one_record_per_learner_and_concept, [nondet]) :-
    set_random(seed(31415)),
    generate_learners(2, 3, Records),
    findall(Concept, concept(Concept), Concepts),
    length(Concepts, ConceptCount),
    length(Records, RecordCount),
    assertion(RecordCount =:= 2 * ConceptCount).

test(scores_are_in_range, [nondet]) :-
    set_random(seed(2718)),
    generate_learners(3, 3, Records),
    forall(member(record(_,_,_,_,_,_,_,_,Mastery,Correct,Total), Records),
           ( assertion(memberchk(Mastery, [true,false])),
             assertion(Total =:= 3),
             assertion(Correct >= 0),
             assertion(Correct =< Total) )).

test(survey_profile_and_concept_ratings_use_defined_values, [nondet]) :-
    set_random(seed(1618)),
    generate_learners(1, 1,
        [record(_,Age,Education,Goal,Experience,Hours,Concept,Rating,_,_,_ )|_]),
    assertion(memberchk(Age, [7,8,10,12,16,18,25,40])),
    assertion(memberchk(Education, [grade_1_entry,elementary,secondary,postsecondary])),
    assertion(memberchk(Goal, [division,fractions,decimals,exponents])),
    assertion(memberchk(Experience, [none,some,substantial])),
    assertion(memberchk(Hours, [1,2,4,6,8])),
    assertion(concept(Concept)),
    assertion(memberchk(Rating, [unfamiliar,vaguely_familiar,familiar,confident,not_sure])).

test(ratings_are_per_concept_not_global, [nondet]) :-
    set_random(seed(222)),
    generate_learners(1, 1, Records),
    findall(Concept-Rating,
        member(record(1,_,_,_,_,_,Concept,Rating,_,_,_), Records), Ratings),
    length(Ratings, RatingCount),
    findall(Concept, concept(Concept), Concepts),
    length(Concepts, ConceptCount),
    assertion(RatingCount =:= ConceptCount).

:- end_tests(synthetic_students).
