<?xml version="1.0" encoding="us-ascii"?>
<!--
	The horse's parent animation database.

	The horse already has a `Rear` fragment playing `relaxed_rearing`, but a
	fragment is not something Lua can ask for. `StartInteractiveActionByName`
	resolves its argument against the FragTags of exactly one fragment,
	`AnimationControlled`, and the horse has none, the same situation the women
	were in before `wh_female_fragmentids.xml`.

	So this declares `AnimationControlled` for the horse and gives it one
	option, `hcm_rear`, whose contents are vanilla's own `Rear` fragment copied
	verbatim: the same clip and the same MovementControlMethod parameters. The
	vanilla database is referenced as a SubADB rather than replaced, so every
	other horse animation resolves exactly as it did and no other mod editing
	horse animations is disturbed.

	The parent has to be the one defining `AnimationControlled`, because a
	sub-database cannot merge options into a fragment its parent already
	defines. Nothing else needs restating here for the same reason: the horse's
	vanilla database owns every other fragment and keeps it.
-->
<AnimDB FragDef="Animations/Mannequin/ADB/kcd_horse_fragmentids.xml" TagDef="Animations/Mannequin/ADB/kcd_horse_tags.xml">
  <FragmentList>
    <AnimationControlled>
      <Fragment BlendOutDuration="0.6" Tags="" FragTags="hcm_rear">
        <AnimLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Animation name="relaxed_rearing" />
          <!--
            The rear ends when the rear is over and the landing has settled.

            `relaxed_rearing` is 2.06 s. The front hooves hit the ground around
            1.4 s, but the horse's legs and spine spend the next ~350 ms absorbing
            the landing impact and recovering to neutral stance. Cutting at 1.4 s
            cuts the horse in mid-compression, causing a visible snap into idle.
            Moving ExitTime to 1.8 s lets the settle finish smoothly before
            handing back to MotionIdle.
          -->
          <Blend ExitTime="1.8" StartTime="0" Duration="0.3" terminal="1" />
          <Animation name="" />
        </AnimLayer>
        <ProcLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Procedural type="MovementControlMethod">
            <ProceduralParams>
              <!--
                Vanilla's own values otherwise, kept after trying the opposite.
                Freeing XyMove and Rotate does not stop the horse being
                displaced, it makes it worse: with the animation no longer
                owning position the horse drifts under its own physics,
                measured at 0.80 m and described as a metre to the right.

                `Horizontal` is the movement control method itself, and the
                header gives the values: `eMCM_Entity = 1`, `eMCM_Animation =
                2`. Setting it to 1 was tried here and made the rear look
                exactly as it did before any of this work, so 2 stays.
              -->
              <Horizontal value="0" />
              <Vertical value="0" />
              <!--
                XyMove=0 prevents both the front-end and tail-end snaps.

                During AnimationControlled, the engine freezes the physics proxy
                at the horse's position when Enter() fires (confirmed in
                CActionInteractive::vfunction5 via decomp: the vtable+0x538 call
                releases the kinematic lock on Exit). With XyMove=1 the visual
                mesh accumulates the animation's root motion and diverges from
                the frozen physics proxy; when the lock releases the visual
                snaps back to the proxy.

                With XyMove=0 the animation does NOT move the horse's XY root,
                so the visual mesh never diverges from the frozen proxy, and
                Exit() has nothing to snap back to. The horse stays in place
                while the animation plays. Velocity is zeroed in Rear.lua before
                the action fires so the horse does not drift under its own
                physics while the proxy is frozen.

                The previous test that found 0.80m drift used XyMove=0 without
                zeroing velocity first; that drift was physics drift, not root
                motion. With SetVelocity({0,0,0}) before the action, XyMove=0
                is safe.
              -->
              <XyMove value="0" />
              <ZMove value="1" />
              <!--
                Rotation is left to the horse. This is the displacement, and it
                is the one parameter here never tested on its own.

                The reproduction is exact: standing still and rearing shows no
                displacement worth mentioning, and turning the horse first and
                then rearing shows it plainly. A horse that is already turning
                carries angular momentum into a fragment that takes rotation
                away from it for the fragment's whole length, and the
                suppressed rotation is discharged in one frame at the end. That
                is the horse finishing turned slightly, or a tenth of a metre
                across, and on the charge it is the diagonal pull.

                Nothing that moves the end of the fragment can help, which is
                why `ExitTime` at 1.4 and 1.75, `Duration` at 0.2 and 0.6, and
                `Horizontal` at 1 all left it exactly as it was. Those change
                when the divergence is discharged, never whether it builds up.

                The note above rules this out on the strength of a test that
                freed `XyMove` and `Rotate` together and measured 0.80 m of
                drift. Drift in metres is `XyMove`, so `XyMove` stays at 1 and
                only rotation is handed back.
              -->
              <Rotate value="0" />
              <Velocity value="0" />
              <Inertia value="0" />
            </ProceduralParams>
          </Procedural>
        </ProcLayer>
      </Fragment>
      <!--
        Rear and drive forward, as one fragment rather than two.

        Chaining two separate calls always showed a gap, because
        `relaxed_rearing` spends its last third back on all fours doing
        nothing while the fragment still owns the horse: the clip releases at
        2064 ms and the rear is visually over around 1400. Firing the lunge
        into that tail either clipped it, at 700 ms, or still read as a pause,
        at 1400 and 1900.

        A second Blend in the same AnimLayer cuts the first clip at its
        ExitTime and blends into the next, which is how vanilla's own gallop
        jump moves from its take-off to its fall loop. So the rearing clip is
        cut at 1.3 s and hands straight to the jump.

        The movement control has to change with it. The rear needs the
        animation to own position, or momentum drags the horse sideways; the
        jump needs it free with inertia on, or it cannot travel. A second
        Blend in the ProcLayer switches at the same moment.
      -->
      <Fragment BlendOutDuration="0.2" Tags="" FragTags="hcm_rear_charge">
        <!--
          The charge covers no distance.

          It used to blend into `relaxed_gallop_jump`, whose root motion carried
          the horse 5.4 m. An interactive action moves the actor kinematically
          with collision off, so that travel went through walls, wedged in
          fences, and accumulated a divergence the engine discharged at over
          20 m/s. All three movement control methods were measured and none
          gives travel and collision together.

          So the animation only rears, in place, and the travel is a physical
          impulse applied once this action has ended. The horse is then an
          ordinary moving horse: it collides, it reports a real velocity, and
          the collision loop scores it exactly like a gallop.
        -->
        <AnimLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Animation name="relaxed_rearing" />
          <!--
            The rear is cut at 0.8 s and finished with a landing.

            `relaxed_rearing` runs 2.06 s and spends its last third back on
            all fours doing nothing, and the impulse cannot be applied until
            the interactive action ends, so that tail was the delay between
            the rear and the horse moving. Speeding the clip up shortens the
            useful part with the dead part and looks wrong.

            `relaxed_idle_jump_land` is a horse coming down onto its front
            feet, which is the shape the rear ends in, and it does not loop,
            so the action ends when it does.
          -->
          <!--
            `StartTime` skips into the landing rather than playing it whole.
            Measured, the action ended 1856 ms after the charge began with the
            rear blending out at 1.0 s, so the landing was running 856 ms and
            every one of them was dead time: the impulse cannot fire until the
            interactive action ends.

            The front of a jump landing is the airborne part, which a horse
            coming down from a rear has already done, so skipping it costs
            nothing to look at and buys the whole of that time back.
          -->
          <Blend ExitTime="1.0" StartTime="0.45" Duration="0.2" />
          <Animation name="relaxed_idle_jump_land" />
          <!--
            The landing is cut 0.05 s in, and the fragment ends there.

            A blend paired with an empty animation is a clip that plays
            nothing, and `terminal` ends the sequence on it. This is what gives
            the tail of the last clip an end time, which `ExitTime` and
            `StartTime` between them do not: they cut the previous clip and
            skip into the incoming one, so without this only the front of a
            clip is controllable.

            It matters here because the lunge impulse cannot fire until the
            interactive action ends, so every millisecond of the landing that
            plays after the horse is down is delay. Measured on the
            `ChargeForward ... after=` line: 1408 ms before, 1040 to 1072 ms
            after, with no warning logged.

            The empty `<Animation>` is load bearing rather than decoration. A
            fragment sizes its clip array at `childCount / 2`, so a trailing
            `<Blend>` on its own leaves five children, still sizes the array at
            two, and writes a third clip past the end of it. The pair keeps the
            count even and the write in bounds. Only a transition blend gets
            the spare slot that would make a lone terminal blend safe.
          -->
          <Blend ExitTime="0.05" StartTime="0" Duration="0.1" terminal="1" />
          <Animation name="" />
        </AnimLayer>
        <ProcLayer>
          <Blend ExitTime="0" StartTime="0" Duration="0.2" />
          <Procedural type="MovementControlMethod">
            <ProceduralParams>
              <Horizontal value="2" />
              <Vertical value="0" />
              <XyMove value="1" />
              <ZMove value="1" />
              <Rotate value="1" />
              <Velocity value="0" />
              <Inertia value="0" />
            </ProceduralParams>
          </Procedural>
        </ProcLayer>
      </Fragment>
    </AnimationControlled>
  </FragmentList>
  <SubADBs>
    <SubADB File="Animations/Mannequin/ADB/kcd_horse_database.adb" />
  </SubADBs>
</AnimDB>
