# Desktop wait deadline regression

The pinned `org.jetbrains.compose.ui:ui-test-desktop:1.7.1` artifact's
`SkikoComposeUiTest.waitUntil` computes a timeout message but discards it instead
of throwing. An unsatisfied predicate continues rendering indefinitely. This
initially appeared in thread dumps as repeated Skia `Canvas.drawPicture` work;
CPU sampling and a software-renderer rerun ruled out a blocked GPU call.

`javap -c -p` on the resolved jar showed this timeout branch:

```text
52: lload_2
53: aload_1
54: invokestatic ComposeUiTestKt.buildWaitUntilTimeoutMessage
57: pop
58: goto 20
```

`CupertinoTestWait.kt` now wraps the normal test clock with an independent
`System.nanoTime` deadline that throws `AssertionError` from the predicate.
The vendored picker regression project enforces the same deadline independently.
No Compose binary or application renderer was modified for this test issue.
Failed state predicates are reported as test failures rather than hanging a run.
