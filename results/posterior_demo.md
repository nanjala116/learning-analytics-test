# Synthetic posterior-update examples

These examples show the current estimator applied to a **seeded synthetic cohort**, not real learners. The 20 generated learners each have 12 concept assessments with 3 randomized item outcomes per concept. See [`posterior_examples.csv`](posterior_examples.csv) for all 240 concept-level rows and [`generate_posterior_examples.pl`](generate_posterior_examples.pl) for the reproducible generator. The simulator's `hidden_mastery` value is deliberately omitted from the estimator inputs and the exported analysis.

## How a score updates the estimate

For a prior mastery probability \(p\), \(C\) correct answers out of \(N\), probability of a correct answer if mastered \(q_M=0.80\), probability if not mastered \(q_N=0.45\), and fractional evidence weight \(\lambda=0.25\), the implementation is:

\[
P(M\mid C,N)=\frac{p\,[q_M^C(1-q_M)^{N-C}]^{\lambda}}
{p\,[q_M^C(1-q_M)^{N-C}]^{\lambda}+(1-p)\,[q_N^C(1-q_N)^{N-C}]^{\lambda}}.
\]

Equivalently, posterior odds equal prior odds multiplied by the per-test likelihood ratio raised to 0.25. The fractional exponent tempers the impact of one test. Zero evidence (0/0) leaves the prior unchanged. When both a concept familiarity prior and an education prior are defined, this prototype averages them; otherwise it uses the available prior. Concepts without a direct survey or education prior can inherit a prior from prerequisite estimates, using the documented independence approximation.

For a fixed prior of 0.80 and a 10-item assessment, the exact current-code results are:

| Score | Posterior mastery estimate | Interpretation |
|---:|---:|---|
| 0/10 | 24.18% | Strong downward evidence, but not certainty |
| 5/10 | 69.87% | Posterior remains above 50% despite a middling score |
| 8/10 | 88.40% | Positive evidence raises an already-high prior |

These are confidence estimates from the prototype's likelihood assumptions, not score bands. The action policy separately classifies raw percentage scores.

## Different synthetic students: addition

The seeded cohort illustrates that both a survey-informed prior and the randomized score matter. These rows are selected examples from the full CSV:

| Student | Education | Familiarity | Score | Prior | Posterior |
|---:|---|---|---:|---:|---:|
| 3 | postsecondary | confident | 0/3 | 0.8000 | 0.6519 |
| 10 | grade_1_entry | vaguely_familiar | 0/3 | 0.2750 | 0.1508 |
| 11 | grade_1_entry | confident | 3/3 | 0.5000 | 0.6062 |
| 15 | elementary | confident | 3/3 | 0.8500 | 0.8972 |
| 16 | elementary | not_sure | 1/3 | 0.9000 | 0.8624 |
| 17 | grade_1_entry | vaguely_familiar | 3/3 | 0.2750 | 0.3687 |

The same score does not imply the same posterior for every student: priors differ, and for non-root concepts prerequisite estimates can also affect the starting prior. Conversely, the same prior can lead to different posteriors when the randomized scores differ. Because each concept test has only three items in this cohort, updates are modest under \(\lambda=0.25\); a single 3/3 result should not be read as proof of mastery.

In this seeded synthetic sample, addition posteriors ranged from 0.1508 to 0.8972. This range describes only this random seed and these hard-coded assumptions; it is not a population estimate, model validation, or evidence that the prior mappings are well calibrated. The simulator currently assigns background descriptors and self-ratings independently of hidden mastery. The estimator also does not model learning caused by lessons, summaries, or retakes.

## Reproduce

From the repository root:

```bash
swipl -q -s results/generate_posterior_examples.pl \
  -g "set_random(seed(123)),write_posterior_examples('results/posterior_examples.csv',20),halt"

swipl -q -s estimate_mastery.pl -g run_tests -t halt
swipl -q -s simulate_students.pl -g run_tests -t halt

swipl -q -s estimate_mastery.pl -g "set_random(seed(123)),evaluate_synthetic(20,Accuracy,Brier),format('Accuracy=~3f Brier=~3f~n',[Accuracy,Brier]),halt"
```

The seeded synthetic evaluation returned accuracy 0.713 and Brier score 0.194 on this run. These numbers compare estimates to the simulator's hidden labels and only indicate behavior under the simulator's own assumptions. They should not be presented as real-world accuracy or predictive validation.
