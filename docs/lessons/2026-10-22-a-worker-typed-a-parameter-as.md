What happened: A worker typed a parameter as `Fighter` before that class was committed; CI lint failed on the pushed tree
Rule: Code against an uncommitted contract class with duck typing (`Node3D`), and lint a clean clone before pushing when workers are mid-flight
