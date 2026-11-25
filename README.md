# Arithmetic Learning Prototype

A small SWI-Prolog prototype for prerequisite-aware learning paths. It separates concept relationships from path generation and includes basic tests.

## Requirements

- SWI-Prolog 9.x (the script uses standard Prolog plus SWI-Prolog's `plunit` test library)

## Run the tests

```bash
swipl -q -s estimate_mastery.pl -g run_tests -t halt
```

## Try a query interactively

```bash
swipl -s arithmetic_path.pl
```

Then query, for example:

```prolog
?- learning_path(division, [addition, multiplication], Path).
?- next_concept_to_learn(division, [counting_and_number_sense, place_value, number_types], Concept).
```

The prototype now includes prerequisite-aware path generation, synthetic data, and a simple probabilistic score-based mastery estimator. The estimator is an approximate baseline, not exact Bayesian-network inference.

## Generate synthetic learner and quiz data

Generate 20 fictional learners, with three randomized quiz items per concept:

```bash
swipl -q -s simulate_students.pl -g "write_synthetic_csv('synthetic_students.csv',20),halt"
```

For repeatable output while testing, set a random seed first:

```bash
swipl -q -s simulate_students.pl -g "set_random(seed(123)),write_synthetic_csv('synthetic_students.csv',20),halt"
```

The CSV includes age, education level, learning goal, prior math exposure, study hours, a **concept-specific** familiarity rating, concept-level correct/total answers, and `hidden_mastery`. Each concept row gets its own rating on `unfamiliar`, `vaguely_familiar`, `familiar`, `confident`, or `not_sure`; there is no single global confidence value. The survey values are synthetic and are not currently used to generate hidden mastery. `hidden_mastery` is simulator ground truth for evaluation and must not be given to the estimator.

Run the path, simulator, and estimator tests together with:

```bash
swipl -q -s estimate_mastery.pl -g run_tests -t halt
```

## Estimate mastery and evaluate against simulation truth

Evaluate on 20 reproducibly generated learners:

```bash
swipl -q -s estimate_mastery.pl -g "set_random(seed(123)),evaluate_synthetic(20,Accuracy,Brier),format('Accuracy=~3f Brier=~3f~n',[Accuracy,Brier]),halt"
```

The estimator uses each concept's latest correct/total score to update a mastery probability. It forms a survey-informed starting prior for rated concepts and a prerequisite-informed prior where the survey has no applicable rating. `diagnostic_for_target/4` reports confidence for the target, its prerequisites, and potential gaps. `score_policy_actions/2` separately returns the available action options for the learner's current score bands.

The current dependency calculation uses an independence approximation when combining uncertain parent probabilities. The generator and estimator intentionally share provisional probabilities, so good synthetic evaluation results only show that the pipeline is internally consistent. They do not validate real-world mastery probabilities; use real pilot data and separately calibrated assumptions for that.

### Softer confidence updates

The estimator currently uses illustrative response rates of 0.80 correct if mastered and 0.45 correct if not mastered, with `evidence_weight(0.25)`. The likelihood ratio for one test is raised to this fractional power before updating prior odds. This tempers the effect of a single assessment; it does not model learning after an intervention or establish empirically calibrated probabilities. The simulator uses the same response rates so synthetic evaluation remains internally aligned.

`diagnostic_for_target(Target, Attempts, Survey, Diagnostic)` returns a target confidence, confidence labels for prerequisite ancestors, and a list of prerequisites with posterior below 0.50 tagged `potential_gap`. Confidence is the BN posterior expressed as a percentage; it should be presented as the model's current estimate, not a guarantee of mastery. Score-band actions remain a separate policy.

Example query:

```prolog
?- diagnostic_for_target(division, Attempts, Survey, Diagnostic).
```

## Score-based action policy

`score_policy_actions/2` accepts attempts in the form `attempt(Concept,Correct,Total)`, listed oldest first. It retains earlier attempts as history but uses only the latest attempt per concept for the current score and action. Its integer-percent bands are:

- 80% and above: mastered; no additional action recommended by this rule.
- 50% to below 80%: passed, but recommend more practice.
- 30% to below 50%: weak; summary first, with full review as an option.
- Below 30%: very weak; full material review first, with concept review also allowed.

If a learner passes an advanced concept while an assessed prerequisite is weak or very weak, the policy retains both results and adds `retake_test` for that prerequisite. This is a review trigger, not an automatic rewrite of BN parameters. Recommendations are lists of available actions; a learner may choose one or a combination.

Example:

```prolog
?- score_policy_actions([attempt(multiplication,2,5),attempt(division,9,10)], Actions).
```

This classifies division as mastered and multiplication as weak, recommends a multiplication summary, and flags a multiplication retest because division was passed. To represent a retake, append a new `attempt/3` for that concept; do not add it to the earlier attempt. For example, `attempt(addition,5,20)` followed later by `attempt(addition,12,20)` means the current addition result is 12/20, while 5/20 remains in the history.

## Questions, assessment attempts, and learner survey

Question-to-concept links are stored as `question_concept(QuestionId,Concept)`. The current file includes one illustrative item per concept; replace these with the actual question bank. For a question that intentionally measures more than one concept, add more than one mapping fact. Responses are recorded per assessment attempt as `assessment_attempt(AttemptId,Sequence,[response(QuestionId,correct|incorrect),...])`. `current_concept_scores/2` maps the answers through the question catalog and selects the highest-sequence attempt that contains evidence for each concept. Earlier attempts remain available as history and are not summed into the current score. A separate final cumulative assessment should be represented as its own assessment type when implemented; it should not overwrite concept-test results.

The survey term is `survey(AgeYears,EducationLevel,PriorMathExposure,[rating(Concept,LikertResponse),...],LearningGoal)`. Responses use `unfamiliar`, `vaguely_familiar`, `familiar`, `confident`, or `not_sure`. Familiarity maps to provisional starting priors 0.15, 0.35, 0.60, and 0.80 respectively; `not_sure` contributes no familiarity prior. Where configured, education priors include addition 0.20 for `grade_1_entry` and 0.90 for `elementary`. If both an education prior and a familiarity prior exist for the same concept, the prototype takes their simple average; if only one exists, it uses that value. These are assumptions to test, not validated population estimates. Age, prior math exposure, and learning goal are recorded but do not yet affect the priors.
