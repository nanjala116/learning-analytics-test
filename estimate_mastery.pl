/*
  Baseline concept-mastery estimator for the synthetic arithmetic prototype.

  Run tests:
    swipl -q -s estimate_mastery.pl -g run_tests -t halt

  Evaluate 20 synthetic learners:
    swipl -q -s estimate_mastery.pl -g "set_random(seed(123)),evaluate_synthetic(20,Accuracy,Brier),format('Accuracy=~3f Brier=~3f~n',[Accuracy,Brier]),halt"

  This is a transparent approximate inference baseline, not exact BN inference.
  It uses prerequisite-conditioned priors and a binomial quiz-answer likelihood.
*/

:- use_module(library(lists)).
:- use_module(library(plunit)).
:- ensure_loaded(simulate_students).

% Match the provisional simulator assumptions.
root_mastery_prior(0.70).
mastery_if_all_prerequisites_known(0.82).
mastery_if_some_prerequisite_missing(0.12).
% Softer, illustrative answer model plus fractional evidence weight.
probability_correct_if_mastered(0.80).
probability_correct_if_not_mastered(0.45).
evidence_weight(0.25).

% estimate_learner(+Scores, -Estimates)
% Scores:    [score(Concept, CorrectCount, TotalItems), ...]
% Estimates: [estimate(Concept, Prior, Posterior), ...]
% The hidden mastery truth is deliberately not an argument.
estimate_learner(Scores, Estimates) :-
    default_survey(Profile),
    estimate_learner(Scores, Profile, Estimates).

% Profile is survey(AgeYears, EducationLevel, PriorMathExposure,
%                   [rating(Concept, LikertResponse),...], LearningGoal).
estimate_learner(Scores, Profile, Estimates) :-
    findall(Concept, concept(Concept), Concepts0),
    sort(Concepts0, Concepts),
    topological_order(Concepts, Ordered),
    estimate_in_order(Ordered, Scores, Profile, [], Estimates).

estimate_in_order([], _, _, _, []).
estimate_in_order([Concept|Rest], Scores, Profile, Previous,
                  [estimate(Concept, Prior, Posterior)|Estimates]) :-
    prerequisite_prior(Concept, Profile, Previous, Prior),
    score_for(Concept, Scores, Correct, Total),
    posterior_from_score(Prior, Correct, Total, Posterior),
    estimate_in_order(Rest, Scores, Profile,
                      [estimate(Concept, Prior, Posterior)|Previous], Estimates).

% Editable initial survey schema and illustrative education-conditioned priors.
default_survey(survey(18, secondary, some, [], arithmetic)).

% These are demo assumptions, not validated learner statistics. Add or revise
% rows when there is evidence; the specific contrast is intentionally visible.
background_prior(education_level(elementary), addition, 0.90).
background_prior(education_level(grade_1_entry), addition, 0.20).

% Set the education prior for root concepts when known; otherwise use the
% generic root prior. Other survey fields are collected but not yet causal.
profile_root_prior(Profile, Concept, Prior) :-
    profile_concept_prior(Profile, Concept, Prior), !.
profile_root_prior(_, _, Prior) :-
    root_mastery_prior(Prior).

% Each authored question maps to the concept it assesses. Multiple mappings
% for one question are allowed when an item intentionally assesses multiple
% concepts.
question_concept(q_counting_01, counting_and_number_sense).
question_concept(q_place_value_01, place_value).
question_concept(q_number_types_01, number_types).
question_concept(q_addition_01, addition).
question_concept(q_subtraction_01, subtraction).
question_concept(q_multiplication_01, multiplication).
question_concept(q_fractions_01, fractions).
question_concept(q_decimals_01, decimals).
question_concept(q_division_01, division).
question_concept(q_exponents_01, exponents).
question_concept(q_logarithms_01, logarithms).
question_concept(q_operation_properties_01, operation_properties).

% assessment_attempt(AttemptId, Sequence, [response(QuestionId,correct|incorrect),...])
% Attempts are retained as history. For current results, only the latest
% attempt containing mapped answers for each concept is selected.
score_from_responses(Responses, Concept, Correct, Total) :-
    findall(Result,
            (member(response(Question, Result), Responses),
             question_concept(Question, Concept),
             memberchk(Result, [correct, incorrect])),
            Results),
    length(Results, Total),
    include(=(correct), Results, CorrectResults),
    length(CorrectResults, Correct),
    Total > 0.

current_concept_scores(Attempts, Scores) :-
    findall(Concept, question_concept(_, Concept), Concepts0),
    sort(Concepts0, Concepts),
    findall(score(Concept, Correct, Total),
            (member(Concept, Concepts),
             latest_concept_attempt(Attempts, Concept, Correct, Total)),
            Scores).

latest_concept_attempt(Attempts, Concept, Correct, Total) :-
    findall(Sequence-(C-T),
            (member(assessment_attempt(_, Sequence, Responses), Attempts),
             score_from_responses(Responses, Concept, C, T)),
            Results),
    keysort(Results, Sorted),
    last(Sorted, _-(Correct-Total)).

score_policy_from_assessments(Attempts, Actions) :-
    current_concept_scores(Attempts, Scores),
    findall(attempt(Concept, Correct, Total),
            member(score(Concept, Correct, Total), Scores), CurrentAttempts),
    score_policy_actions(CurrentAttempts, Actions).

estimate_assessment_attempts(Attempts, Profile, Estimates) :-
    current_concept_scores(Attempts, Scores),
    estimate_learner(Scores, Profile, Estimates).

% Diagnostic includes target confidence, confidence on prerequisite ancestors,
% and prerequisites whose posterior is below 0.50 as potential gaps.
diagnostic_for_target(Target, Attempts, Profile,
    diagnostic(Target, TargetConfidence, PrerequisiteConfidence, PotentialGaps)) :-
    estimate_assessment_attempts(Attempts, Profile, Estimates),
    confidence_for(Estimates, Target, TargetConfidence),
    findall(Ancestor, prerequisite_ancestor(Ancestor, Target), Ancestors0),
    sort(Ancestors0, Ancestors),
    maplist(concept_confidence(Estimates), Ancestors, PrerequisiteConfidence),
    include(is_potential_gap, PrerequisiteConfidence, PotentialGaps).

confidence_for(Estimates, Concept, confidence(Concept, Percent, Label)) :-
    memberchk(estimate(Concept, _, Probability), Estimates),
    Percent is Probability * 100,
    confidence_label(Probability, Label).

concept_confidence(Estimates, Concept, Confidence) :-
    confidence_for(Estimates, Concept, Confidence).

confidence_label(Probability, high_confidence) :- Probability >= 0.80, !.
confidence_label(Probability, uncertain) :- Probability >= 0.50, !.
confidence_label(_, potential_gap).

is_potential_gap(confidence(_, _, potential_gap)).

% ---- Score policy and prerequisite mismatch handling ----
% The policy uses integer-percent cutoffs, avoiding rounded display values:
% 80%+ mastered; 50%-<80% passed but needs practice;
% 30%-<50% weak; below 30% very weak.
score_band(Correct, Total, Band) :-
    integer(Correct), integer(Total), Total > 0,
    Correct >= 0, Correct =< Total,
    PercentNumerator is Correct * 100,
    (   PercentNumerator >= Total * 80 -> Band = mastered
    ;   PercentNumerator >= Total * 50 -> Band = passed_needs_practice
    ;   PercentNumerator >= Total * 30 -> Band = weak
    ;   Band = very_weak
    ).

% Actions for each concept with evidence, using only the latest attempt.
% Attempts must be chronological, oldest first. Earlier attempts remain in the
% supplied history but are not combined into the current score.
% attempts: [attempt(Concept, Correct, Total), ...]
% actions:  [action(Concept, Band, Recommendation), ...]
score_policy_actions(Attempts, Actions) :-
    latest_attempt_scores(Attempts, Scores),
    findall(action(Concept, Band, Recommendation),
            (member(score(Concept, Correct, Total), Scores),
             score_band(Correct, Total, Band),
             recommendation_for_band(Band, Recommendation)),
            BaseActions),
    findall(action(Prerequisite, retest_recommended, [retake_test]),
            (member(score(Advanced, AdvancedCorrect, AdvancedTotal), Scores),
             score_band(AdvancedCorrect, AdvancedTotal, AdvancedBand),
             memberchk(AdvancedBand, [mastered, passed_needs_practice]),
             prerequisite_ancestor(Prerequisite, Advanced),
             member(score(Prerequisite, PreCorrect, PreTotal), Scores),
             score_band(PreCorrect, PreTotal, PreBand),
             memberchk(PreBand, [weak, very_weak])),
            RetestActions0),
    sort(RetestActions0, RetestActions),
    append(BaseActions, RetestActions, Actions).

recommendation_for_band(mastered, []).
recommendation_for_band(passed_needs_practice, [view_summary, retake_test]).
recommendation_for_band(weak, [view_summary, review_course]).
recommendation_for_band(very_weak, [review_course, view_summary]).

% Select the last chronological attempt for each concept. Do not sum attempts.
latest_attempt_scores(Attempts, Scores) :-
    findall(Concept, member(attempt(Concept, _, _), Attempts), Concepts0),
    sort(Concepts0, Concepts),
    maplist(latest_attempt_score(Attempts), Concepts, Scores).

latest_attempt_score(Attempts, Concept, score(Concept, Correct, Total)) :-
    findall(C-T, member(attempt(Concept, C, T), Attempts), Results),
    last(Results, Correct-Total),
    integer(Correct), integer(Total), Total > 0,
    Correct >= 0, Correct =< Total.

prerequisite_ancestor(Ancestor, Target) :-
    prerequisite(Ancestor, Target).
prerequisite_ancestor(Ancestor, Target) :-
    prerequisite(Intermediate, Target),
    prerequisite_ancestor(Ancestor, Intermediate).

% Missing direct test evidence leaves the concept at its prerequisite-informed prior.
score_for(Concept, Scores, Correct, Total) :-
    memberchk(score(Concept, Correct, Total), Scores), !.
score_for(_, _, 0, 0).

prerequisite_prior(Concept, Profile, _, Prior) :-
    profile_concept_prior(Profile, Concept, Prior), !.
prerequisite_prior(Concept, Profile, _, Prior) :-
    findall(Parent, prerequisite(Parent, Concept), []), !,
    profile_root_prior(Profile, Concept, Prior).
prerequisite_prior(Concept, _, Previous, Prior) :-
    findall(Parent, prerequisite(Parent, Concept), Parents),
    parent_product(Parents, Previous, ProbabilityAllParents),
    mastery_if_all_prerequisites_known(High),
    mastery_if_some_prerequisite_missing(Low),
    Prior is High * ProbabilityAllParents + Low * (1.0 - ProbabilityAllParents).

profile_concept_prior(survey(_, Education, _, Ratings, _), Concept, Prior) :-
    optional_familiarity_prior(Ratings, Concept, FamiliarityPrior),
    optional_education_prior(Education, Concept, EducationPrior),
    !,
    combine_optional_priors(FamiliarityPrior, EducationPrior, Prior).

optional_familiarity_prior(Ratings, Concept, Prior) :-
    memberchk(rating(Concept, Rating), Ratings),
    familiarity_prior(Rating, Prior), !.
optional_familiarity_prior(_, _, none).

optional_education_prior(Education, Concept, Prior) :-
    background_prior(education_level(Education), Concept, Prior), !.
optional_education_prior(_, _, none).

combine_optional_priors(Familiarity, Education, Prior) :-
    number(Familiarity), number(Education), !,
    Prior is (Familiarity + Education) / 2.0.
combine_optional_priors(Familiarity, _, Familiarity) :- number(Familiarity), !.
combine_optional_priors(_, Education, Education) :- number(Education).

% These map survey labels to starting mastery probabilities for the prototype.
% They are editable assumptions, not empirically calibrated mappings.
familiarity_prior(unfamiliar, 0.15).
familiarity_prior(vaguely_familiar, 0.35).
familiarity_prior(familiar, 0.60).
familiarity_prior(confident, 0.80).

parent_product([], _, 1.0).
parent_product([Parent|Rest], Estimates, Product) :-
    memberchk(estimate(Parent, _, ParentPosterior), Estimates),
    parent_product(Rest, Estimates, RestProduct),
    Product is ParentPosterior * RestProduct.

posterior_from_score(Prior, 0, 0, Prior) :- !.
posterior_from_score(Prior, Correct, Total, Posterior) :-
    evidence_weight(Lambda),
    posterior_from_score(Prior, Correct, Total, Lambda, Posterior).

posterior_from_score(Prior, 0, 0, _, Prior) :- !.
posterior_from_score(Prior, Correct, Total, Lambda, Posterior) :-
    integer(Correct), integer(Total),
    Correct >= 0, Total > 0, Correct =< Total,
    number(Lambda), Lambda > 0.0, Lambda =< 1.0,
    probability_correct_if_mastered(PCorrectKnown),
    probability_correct_if_not_mastered(PCorrectUnknown),
    Incorrect is Total - Correct,
    RawLikelihoodKnown is PCorrectKnown ** Correct * (1.0 - PCorrectKnown) ** Incorrect,
    RawLikelihoodUnknown is PCorrectUnknown ** Correct * (1.0 - PCorrectUnknown) ** Incorrect,
    LikelihoodKnown is RawLikelihoodKnown ** Lambda,
    LikelihoodUnknown is RawLikelihoodUnknown ** Lambda,
    Numerator is Prior * LikelihoodKnown,
    Denominator is Numerator + (1.0 - Prior) * LikelihoodUnknown,
    (Denominator =:= 0.0 -> Posterior = Prior ; Posterior is Numerator / Denominator).

% Evaluation compares inferred posterior probabilities with simulator-only truth.
% It intentionally keeps hidden_mastery out of estimate_learner/2.
evaluate_synthetic(LearnerCount, Accuracy, BrierScore) :-
    generate_learners(LearnerCount, 3, Records),
    findall(Id, member(record(Id,_,_,_,_,_,_,_,_,_,_), Records), Ids0),
    sort(Ids0, Ids),
    evaluate_students(Ids, Records, 0, 0.0, 0, 0, Accuracy, BrierScore).

evaluate_students([], _, CorrectPredictions, BrierTotal, N, _, Accuracy, BrierScore) :-
    (N =:= 0 -> Accuracy = 0.0, BrierScore = 0.0
    ; Accuracy is CorrectPredictions / N,
      BrierScore is BrierTotal / N).
evaluate_students([Id|Rest], Records, Correct0, Brier0, N0, _, Accuracy, BrierScore) :-
    findall(score(Concept, Correct, Total),
            member(record(Id,_,_,_,_,_,Concept,_,_,Correct,Total), Records), Scores),
    findall(Concept,
            member(record(Id,_,_,_,_,_,Concept,_,true,_,_), Records), HiddenMastered),
    estimate_learner(Scores, Estimates),
    score_estimates(Estimates, HiddenMastered, CorrectForStudent, BrierForStudent, Count),
    Correct1 is Correct0 + CorrectForStudent,
    Brier1 is Brier0 + BrierForStudent,
    N1 is N0 + Count,
    evaluate_students(Rest, Records, Correct1, Brier1, N1, 0, Accuracy, BrierScore).

score_estimates([], _, 0, 0.0, 0).
score_estimates([estimate(Concept, _, Posterior)|Rest], Hidden,
                 CorrectCount, BrierTotal, Count) :-
    (memberchk(Concept, Hidden) -> Truth = 1.0 ; Truth = 0.0),
    (Posterior >= 0.5, Truth =:= 1.0 -> CorrectHere = 1
    ; Posterior < 0.5, Truth =:= 0.0 -> CorrectHere = 1
    ; CorrectHere = 0),
    BrierHere is (Posterior - Truth) ** 2,
    score_estimates(Rest, Hidden, CorrectRest, BrierRest, CountRest),
    CorrectCount is CorrectHere + CorrectRest,
    BrierTotal is BrierHere + BrierRest,
    Count is CountRest + 1.

:- begin_tests(mastery_estimator).

test(correct_answers_raise_posterior) :-
    posterior_from_score(0.5, 3, 3, AllCorrect),
    posterior_from_score(0.5, 0, 3, AllWrong),
    assertion(AllCorrect > 0.5),
    assertion(AllWrong < 0.5).

test(no_direct_evidence_preserves_prior) :-
    posterior_from_score(0.63, 0, 0, Posterior),
    assertion(abs(Posterior - 0.63) < 0.000001).

test(learner_estimation_returns_probabilities) :-
    estimate_learner([score(counting_and_number_sense, 2, 3),
                      score(place_value, 3, 3)], Estimates),
    memberchk(estimate(counting_and_number_sense, _, RootPosterior), Estimates),
    memberchk(estimate(place_value, PlacePrior, PlacePosterior), Estimates),
    assertion(RootPosterior >= 0.0),
    assertion(RootPosterior =< 1.0),
    assertion(PlacePrior >= 0.0),
    assertion(PlacePosterior >= 0.0),
    assertion(PlacePosterior =< 1.0).

test(synthetic_evaluation_metrics_in_range, [nondet]) :-
    set_random(seed(909)),
    evaluate_synthetic(5, Accuracy, Brier),
    assertion(Accuracy >= 0.0),
    assertion(Accuracy =< 1.0),
    assertion(Brier >= 0.0),
    assertion(Brier =< 1.0).

test(score_policy_boundaries) :-
    score_band(80, 100, mastered),
    score_band(50, 100, passed_needs_practice),
    score_band(79, 100, passed_needs_practice),
    score_band(49, 100, weak),
    score_band(30, 100, weak),
    score_band(29, 100, very_weak).

test(latest_attempt_supersedes_prior_attempt_for_current_band) :-
    latest_attempt_scores([attempt(addition, 5, 20), attempt(addition, 12, 20)],
                          [score(addition, 12, 20)]),
    score_band(12, 20, passed_needs_practice),
    score_band(5, 20, very_weak).

test(latest_attempt_alone_drives_action_policy) :-
    score_policy_actions([attempt(addition, 5, 20), attempt(addition, 12, 20)], Actions),
    assertion(memberchk(action(addition, passed_needs_practice,
                               [view_summary, retake_test]), Actions)),
    assertion(\+ memberchk(action(addition, very_weak,
                                  [review_course, view_summary]), Actions)).

test(passed_advanced_concept_flags_failed_prerequisite_retest) :-
    score_policy_actions([
        attempt(multiplication, 2, 5),
        attempt(division, 9, 10)
    ], Actions),
    assertion(memberchk(action(division, mastered, []), Actions)),
    assertion(memberchk(action(multiplication, weak,
        [view_summary, review_course]), Actions)),
    assertion(memberchk(action(multiplication, retest_recommended,
        [retake_test]), Actions)).

test(question_responses_are_mapped_and_latest_assessment_wins) :-
    Attempts = [
        assessment_attempt(a1, 1, [response(q_addition_01, incorrect),
                                   response(q_addition_01, incorrect)]),
        assessment_attempt(a2, 2, [response(q_addition_01, correct),
                                   response(q_addition_01, correct),
                                   response(q_addition_01, correct)])
    ],
    current_concept_scores(Attempts, Scores),
    assertion(memberchk(score(addition, 3, 3), Scores)),
    score_policy_from_assessments(Attempts, Actions),
    assertion(memberchk(action(addition, mastered, []), Actions)).

test(survey_education_changes_addition_prior) :-
    estimate_learner([], survey(7, grade_1_entry, none, [], arithmetic), GradeOne),
    estimate_learner([], survey(12, elementary, some, [], arithmetic), Elementary),
    memberchk(estimate(addition, GradeOnePrior, _), GradeOne),
    memberchk(estimate(addition, ElementaryPrior, _), Elementary),
    assertion(GradeOnePrior =:= 0.20),
    assertion(ElementaryPrior =:= 0.90).

test(concept_rating_changes_matching_concept_prior) :-
    Profile = survey(18, secondary, some,
        [rating(addition, confident), rating(division, unfamiliar)], arithmetic),
    estimate_learner([], Profile, Estimates),
    memberchk(estimate(addition, AdditionPrior, _), Estimates),
    memberchk(estimate(division, DivisionPrior, _), Estimates),
    assertion(AdditionPrior =:= 0.80),
    assertion(DivisionPrior =:= 0.15).

test(education_and_concept_rating_are_both_used) :-
    Profile = survey(12, elementary, some,
        [rating(addition, familiar)], arithmetic),
    estimate_learner([], Profile, Estimates),
    memberchk(estimate(addition, AdditionPrior, _), Estimates),
    assertion(abs(AdditionPrior - 0.75) < 0.000001).

test(mapped_test_answers_feed_mastery_estimation) :-
    Profile = survey(10, elementary, some, [], arithmetic),
    Attempts = [assessment_attempt(a1, 1,
        [response(q_addition_01, correct),
         response(q_addition_01, correct),
         response(q_addition_01, correct)])],
    estimate_assessment_attempts(Attempts, Profile, Estimates),
    memberchk(estimate(addition, Prior, Posterior), Estimates),
    assertion(Prior =:= 0.90),
    assertion(Posterior > Prior).

test(fractional_evidence_keeps_single_test_posterior_moderate) :-
    posterior_from_score(0.80, 0, 10, Zero),
    posterior_from_score(0.80, 5, 10, Half),
    posterior_from_score(0.80, 8, 10, High),
    assertion(Zero > 0.20),
    assertion(Zero < 0.30),
    assertion(Half > 0.65),
    assertion(Half < 0.75),
    assertion(High > 0.85),
    assertion(High < 0.92).

test(diagnostic_includes_target_and_prerequisite_confidences) :-
    Profile = survey(18, secondary, some, [], arithmetic),
    Attempts = [assessment_attempt(a1, 1,
        [response(q_multiplication_01, incorrect),
         response(q_division_01, correct)])],
    diagnostic_for_target(division, Attempts, Profile,
        diagnostic(division, confidence(division, _, _), Prereqs, Gaps)),
    assertion(member(confidence(multiplication, _, _), Prereqs)),
    assertion(member(confidence(multiplication, _, potential_gap), Gaps)).

:- end_tests(mastery_estimator).
