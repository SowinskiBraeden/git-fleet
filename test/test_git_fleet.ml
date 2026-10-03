let test_version () =
  Alcotest.(check string)
    "version"
    "0.2.0"
    Git_fleet.Version.value

let () =
  Alcotest.run
    "git-fleet"
    [
      ( "version",
        [
          Alcotest.test_case
            "reports 0.2.0"
            `Quick
            test_version;
        ] );
    ]
