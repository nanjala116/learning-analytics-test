/*
  Reproducible posterior examples for the synthetic arithmetic cohort.

  From the repository root run:
    swipl -q -s results/generate_posterior_examples.pl \
      -g "set_random(seed(123)),write_posterior_examples('results/posterior_examples.csv',20),halt"

  The hidden simulator mastery label is intentionally excluded from the survey
  profile and estimator inputs. These results are illustrative only.
*/
:- ensure_loaded('../estimate_mastery.pl').

write_posterior_examples(File, LearnerCount) :-
    generate_learners(LearnerCount, 3, Records),
    setup_call_cleanup(
        open(File, write, Stream),
        ( write(Stream, 'student_id,education_level,concept,self_reported_familiarity,correct_answers,total_items,prior,posterior\n'),
          findall(Id, member(record(Id,_,_,_,_,_,_,_,_,_,_), Records), Ids0),
          sort(Ids0, Ids),
          forall(member(Id, Ids), write_learner_examples(Stream, Id, Records))
        ),
        close(Stream)).

write_learner_examples(Stream, Id, Records) :-
    member(record(Id, Age, Education, Goal, Experience, _, _, _, _, _, _), Records), !,
    findall(score(Concept, Correct, Total),
        member(record(Id, _, _, _, _, _, Concept, _, _, Correct, Total), Records), Scores),
    findall(rating(Concept, Rating),
        member(record(Id, _, _, _, _, _, Concept, Rating, _, _, _), Records), Ratings),
    Profile = survey(Age, Education, Experience, Ratings, Goal),
    estimate_learner(Scores, Profile, Estimates),
    forall(member(record(Id, _, _, _, _, _, Concept, Rating, _, Correct, Total), Records),
        write_concept_example(Stream, Id, Education, Concept, Rating,
                              Correct, Total, Estimates)).

write_concept_example(Stream, Id, Education, Concept, Rating, Correct, Total, Estimates) :-
    memberchk(estimate(Concept, Prior, Posterior), Estimates),
    format(Stream, '~d,~w,~w,~w,~d,~d,~4f,~4f~n',
        [Id, Education, Concept, Rating, Correct, Total, Prior, Posterior]).
