# frozen_string_literal: true

# Round 2 corpus — noisier, more realistic *form* than Run 12's clean prose.
#
# As in Run 12, every identity is INVENTED. No real person's data is used, and no
# public corpus (Enron etc.) is drawn from. Realism comes from how the text is
# written — quoting, typos, signature blocks, inconsistent naming — not from real
# identities. Emails use RFC-2606 reserved domains; phones use the reserved
# 555-01xx range; SSN-shaped values use the never-issued 900 series.
#
# Tiers (three, deliberately separated so messiness and indirection don't conflate):
#   :obvious — labelled, conventionally-formatted PII
#   :tricky  — Run 12's definition: PII present but indirectly phrased
#   :noisy   — realistic mess: forwarded/quoted chains, typos, abbreviations,
#              inconsistent naming within a document, signature blocks,
#              near-identical names, varied phone formatting
#
# clean: true marks documents containing NO PII at all — these measure the
# false-positive rate on clean input, which Run 12 never tested.
#
# Where a piece of PII repeats across a forwarded thread it is planted ONCE: it is
# one identifier. Scorer#score_document already declines to count duplicate
# findings that match a planted item as false positives.

module DocumentsV2
  TYPES = %w[name email phone address ssn dob].freeze

  ALL = [
    # ───────────────────────────── OBVIOUS ─────────────────────────────
    {
      id: "v2-obv-01", tier: :obvious,
      text: <<~TEXT,
        Hi all,

        Purchase order 4471 is approved. Contact Miriam Halloway at
        miriam.halloway@example.com to arrange collection of the signed copy.

        Regards,
        Procurement
      TEXT
      pii: [
        { type: "name",  text: "Miriam Halloway" },
        { type: "email", text: "miriam.halloway@example.com" }
      ]
    },
    {
      id: "v2-obv-02", tier: :obvious,
      text: <<~TEXT,
        New hire record

        Name: Gerald Vaszquez
        SSN: 900-41-8823
        Date of birth: 11/02/1979

        Start date confirmed for the first of next month. Equipment request
        already submitted.
      TEXT
      pii: [
        { type: "name", text: "Gerald Vaszquez" },
        { type: "ssn",  text: "900-41-8823" },
        { type: "dob",  text: "11/02/1979" }
      ]
    },
    {
      id: "v2-obv-03", tier: :obvious,
      text: <<~TEXT,
        Delivery notice

        Recipient: Constance Bekele
        Address: 903 Windermere Drive, Suite 210, Ann Arbor, MI 48104

        Two pallets, delivered to the loading dock. Signature waived per the
        standing instruction on the account.
      TEXT
      pii: [
        { type: "name",    text: "Constance Bekele" },
        { type: "address", text: "903 Windermere Drive, Suite 210, Ann Arbor, MI 48104" }
      ]
    },
    {
      # Phone format 1 of 3: plain hyphenated.
      id: "v2-obv-04", tier: :obvious,
      text: <<~TEXT,
        MEMO — Building access

        The freight elevator is out until Thursday. Rosalind Achterberg is
        coordinating the repair; reach her on 555-0142 if you need an exception
        for a delivery window.
      TEXT
      pii: [
        { type: "name",  text: "Rosalind Achterberg" },
        { type: "phone", text: "555-0142" }
      ]
    },
    {
      # CLEAN — no PII. Simple, well-formed internal notice.
      id: "v2-obv-05", tier: :obvious, clean: true,
      text: <<~TEXT,
        Reminder

        The quarterly all-hands moves to the larger room on the second floor
        starting this month. Slides are due to the comms channel by end of day
        Wednesday. No dial-in this time — please attend in person if you are on
        site.
      TEXT
      pii: []
    },

    # ───────────────────────────── TRICKY ──────────────────────────────
    {
      id: "v2-trk-01", tier: :tricky,
      text: <<~TEXT,
        Running late — my son's physio, Dr. Ferreira, ran over and I'm still in
        the waiting room. Please push the design review by half an hour if you
        can, otherwise start without me.
      TEXT
      pii: [
        { type: "name", text: "Dr. Ferreira" }
      ]
    },
    {
      id: "v2-trk-02", tier: :tricky,
      text: <<~TEXT,
        Got hold of the Dublin distributor at last. Their direct line is
        +353 1 496 0245 and the person who actually answers is on the trade
        desk, not the front office. Worth noting for next quarter.
      TEXT
      pii: [
        { type: "phone", text: "+353 1 496 0245" }
      ]
    },
    {
      id: "v2-trk-03", tier: :tricky,
      text: <<~TEXT,
        Site visit summary: the annex behind 411 Corriedale Way, Building C,
        Tacoma, WA 98402 is structurally sound but the drainage on the north
        side has clearly been neglected. Recommend a survey before we commit to
        the lease.
      TEXT
      pii: [
        { type: "address", text: "411 Corriedale Way, Building C, Tacoma, WA 98402" }
      ]
    },
    {
      id: "v2-trk-04", tier: :tricky,
      text: <<~TEXT,
        To clarify the earlier thread: Imelda's business partner Rafael Ostrowski
        is the signatory on the account, not Imelda herself. Anything requiring
        authorisation has to go through him.
      TEXT
      pii: [
        { type: "name", text: "Rafael Ostrowski" },
        { type: "name", text: "Imelda" }
      ]
    },
    {
      id: "v2-trk-05", tier: :tricky,
      text: <<~TEXT,
        File note: at the 9 October 2023 assessment the claimant volunteered that
        she had turned 58 two days earlier. That places her inside the extended
        eligibility band, so the standard cutoff does not apply here.
      TEXT
      pii: [
        { type: "dob", text: "turned 58 two days earlier" }
      ]
    },

    # ───────────────────────────── NOISY ───────────────────────────────
    {
      # Forwarded chain, three hops, quoting degrading at each level, headers
      # partially preserved, the same email address repeated down the thread.
      id: "v2-noi-01", tier: :noisy,
      text: <<~TEXT,
        ---------- Forwarded message ----------
        From: Dispatch <dispatch@example.net>
        Subject: Re: Re: FW: pallet shortage

        any update on this? client is asking again

        > On Tue, someone wrote:
        > > yes spoke to the yard. ask for Teodora Brandt, she has the
        > > override code. t.brandt@example.net
        > >
        > > > > > FW: from earlier in the week
        > > > > > we're short 40 pallets and the yard says talk to
        > > > > > t.brandt@example.net -- she's the only one who can release
        > > > > > them out of hours
        > > > > > thanks
      TEXT
      pii: [
        { type: "name",  text: "Teodora Brandt" },
        { type: "email", text: "t.brandt@example.net" },
        { type: "email", text: "dispatch@example.net" }
      ]
    },
    {
      # Informal, typos, abbreviations, inconsistent naming: full name once,
      # then a nickname, then an initial form.
      id: "v2-noi-02", tier: :noisy,
      text: <<~TEXT,
        ok so heads up — Bartholomew Nkemelu is takin over the tues shift from
        me, i already cleared it w/ scheduling. Barty said he can do the early
        start but not the wknd one, so someone els needs to cover sat.

        B. Nkemelu also has the keys for the cage now, dont go looking for them
        in the drawer they arent there anymore
      TEXT
      pii: [
        { type: "name", text: "Bartholomew Nkemelu" }
      ]
    },
    {
      # PII inside a signature block, body itself carries none.
      id: "v2-noi-03", tier: :noisy,
      text: <<~TEXT,
        Confirming we're good to proceed on the revised timeline. Nothing else
        outstanding from my side — send the updated Gantt when you have it.

        --
        Yusuf Karabekir
        Regional Operations
        y.karabekir@example.org
        Direct: 555.0163
        814 Ashcombe Terrace, Floor 4, Providence, RI 02903
      TEXT
      pii: [
        { type: "name",    text: "Yusuf Karabekir" },
        { type: "email",   text: "y.karabekir@example.org" },
        { type: "phone",   text: "555.0163" },
        { type: "address", text: "814 Ashcombe Terrace, Floor 4, Providence, RI 02903" }
      ]
    },
    {
      # Two different people with very similar names in one document.
      id: "v2-noi-04", tier: :noisy,
      text: <<~TEXT,
        Careful with these two, they get mixed up constantly in the system.

        Adrienne Calloway (accounts) approved the credit note. Adrian Calloway
        (warehouse) is the one who signed for the return — different person,
        different site. The duplicate record is why the audit flagged it.

        I've asked IT to merge nothing until we confirm which is which.
      TEXT
      pii: [
        { type: "name", text: "Adrienne Calloway" },
        { type: "name", text: "Adrian Calloway" }
      ]
    },
    {
      # Phone format 3 of 3: parenthesised, plus abbreviation-heavy shorthand.
      id: "v2-noi-05", tier: :noisy,
      text: <<~TEXT,
        pls note the a/h contact for the depot changed last wk. it's now
        (555) 0171 — the old ext is dead, dont bother w/ it. ask for the duty
        mgr, they'll rte you thru. ta
      TEXT
      pii: [
        { type: "phone", text: "(555) 0171" }
      ]
    },
    {
      # Messy quoted reply where a DOB and a partial address are buried in the
      # quoted portion rather than the new text.
      id: "v2-noi-06", tier: :noisy,
      text: <<~TEXT,
        can you check this against the file? doesnt match what i have

        > > from the intake form:
        > > applicant Sunniva Rask, dob 23/07/1991
        > > current addr 12 Rosemount Crescent, Galway, Ireland
        > > says she moved last yr but hasnt updated it
        >
        > i've got a diff address on record, will dig it out
      TEXT
      pii: [
        { type: "name",    text: "Sunniva Rask" },
        { type: "dob",     text: "23/07/1991" },
        { type: "address", text: "12 Rosemount Crescent, Galway, Ireland" }
      ]
    },
    {
      # CLEAN — no PII. Noisy form: forwarded, quoted, typo-laden, but purely
      # logistical. Nothing identifying.
      id: "v2-noi-07", tier: :noisy, clean: true,
      text: <<~TEXT,
        ---------- Forwarded message ----------
        Subject: Re: FW: shelving

        still waiting on the brackets, supplier says end of wk

        > > do we have enough of the short ones to start row 3?
        > >
        > > > i think so but the long ones are definately short
        > > > we counted twice
        > > > might need to reorder before we can finish the run
      TEXT
      pii: []
    },
    {
      # CLEAN — no PII. Informal chat-like with typos and abbreviations,
      # deliberately full of number-ish and name-ish noise that is not PII:
      # room numbers, a product code, a weekday, a department.
      id: "v2-noi-08", tier: :noisy, clean: true,
      text: <<~TEXT,
        moved the standup to rm 214 fyi, the usual room is booked til thurs.
        also SKU 4471-B is the one we're short on not 4471-A, i mixed them up
        earlier sry. finance said theyd sort the reorder but i wouldnt count on
        it happening before mon
      TEXT
      pii: []
    }
  ].freeze

  def self.all = ALL
  def self.by_tier(tier) = ALL.select { it[:tier] == tier }
  def self.clean = ALL.select { it[:clean] }
  def self.ground_truth_count = ALL.sum { it[:pii].size }
end

if __FILE__ == $PROGRAM_NAME
  require "json"
  puts JSON.pretty_generate(
    documents: DocumentsV2.all.size,
    by_tier: DocumentsV2.all.group_by { it[:tier] }.transform_values(&:size),
    clean_documents: DocumentsV2.clean.map { it[:id] },
    ground_truth_items: DocumentsV2.ground_truth_count,
    by_type: DocumentsV2.all.flat_map { it[:pii] }.group_by { it[:type] }.transform_values(&:size)
  )
end
