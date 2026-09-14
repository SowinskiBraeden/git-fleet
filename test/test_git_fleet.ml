let test_version () =
  Alcotest.(check string)
    "version"
    "0.1.0"
    Git_fleet.Version.value

let () =
  Alcotest.run
    "git-fleet"
    [
      ( "version",
        [
          Alcotest.test_case
            "reports 0.1.0"
            `Quick
            test_version;
        ] );
    ]
