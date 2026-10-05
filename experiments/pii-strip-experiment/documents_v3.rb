# frozen_string_literal: true

# Round 3 corpus — structural and adversarial placement.
#
# Identities invented, as in every prior round: RFC-2606 reserved domains,
# 555-01xx reserved phones, 900-series never-issued SSN-shaped values. No public
# dataset, no real person's data.
#
# Runs 12-13 tested PII in *prose*, clean then messy. This round tests placement
# and traps that prose never exercises. Two NEW tiers, deliberately separate from
# obvious/tricky/noisy so these results cannot average into the prior numbers:
#
#   :structural  — layout carries the PII rather than sentences: letterhead
#                  headers, signature blocks, key/value forms, pipe tables, dense
#                  multi-person paragraphs, run-on multi-type sentences, and
#                  OCR/page-break artifacts that split a value across a line.
#   :adversarial — traps for the opposite error: names that are also common words
#                  or place names (false-negative risk), and redaction-flavoured
#                  decoys that look like they are about to contain PII but do not.
#
# clean: true marks documents with NO PII, written in the same dense/structural
# style, to keep measuring false positives on clean input under harder conditions.
#
# Where a document renders a value split across a line break (OCR-style), the
# manifest plants the logical value; Scorer#normalize strips the break, so the
# split and reassembled forms compare identically.

module DocumentsV3
  TYPES = %w[name email phone address ssn dob].freeze

  ALL = [
    # ─────────────────────────── STRUCTURAL ────────────────────────────
    {
      # Letterhead-style header block: PII above the body, not in a sentence.
      id: "v3-st-01", tier: :structural,
      text: <<~TEXT,
        HALVORSEN & REED
        Structural Consultants
        62 Tanner's Wharf, Suite 900, Baltimore, MD 21230
        office 555-0118

        Attn: project team

        The load calculations for the east span are attached. Sign-off is needed
        before the pour scheduled for next week.
      TEXT
      pii: [
        { type: "address", text: "62 Tanner's Wharf, Suite 900, Baltimore, MD 21230" },
        { type: "phone",   text: "555-0118" }
      ]
    },
    {
      # Signature block carries everything; body carries nothing.
      id: "v3-st-02", tier: :structural,
      text: <<~TEXT,
        Approved on our side. Go ahead and release the second tranche whenever
        the paperwork clears.

        --
        Ingrid Solheim-Baptiste
        Director, Capital Projects
        i.solheim@example.org
        m. 555-0127
      TEXT
      pii: [
        { type: "name",  text: "Ingrid Solheim-Baptiste" },
        { type: "email", text: "i.solheim@example.org" },
        { type: "phone", text: "555-0127" }
      ]
    },
    {
      # Pure key/value form. No prose at all.
      id: "v3-st-03", tier: :structural,
      text: <<~TEXT,
        PATIENT INTAKE — PAGE 1

        Surname:        Oyelaran
        Given name:     Folasade
        DOB:            06/14/1972
        SSN:            900-77-3391
        Home phone:     555-0135
        Street:         5511 Juniper Bend Road
        City/State/Zip: Boise, ID 83702
      TEXT
      pii: [
        { type: "name",    text: "Folasade Oyelaran" },
        { type: "dob",     text: "06/14/1972" },
        { type: "ssn",     text: "900-77-3391" },
        { type: "phone",   text: "555-0135" },
        { type: "address", text: "5511 Juniper Bend Road" }
      ]
    },
    {
      # Pipe-delimited table, three distinct people, one row each.
      id: "v3-st-04", tier: :structural,
      text: <<~TEXT,
        ON-CALL ROSTER — Q4

        | Name              | Contact                     | Ext      |
        |-------------------|-----------------------------|----------|
        | Devendra Kulkarni | d.kulkarni@example.com      | 555-0144 |
        | Marguerite Oyono  | m.oyono@example.com         | 555-0151 |
        | Anselm Thackeray  | a.thackeray@example.com     | 555-0166 |

        Swaps must be logged before the shift, not after.
      TEXT
      pii: [
        { type: "name",  text: "Devendra Kulkarni" },
        { type: "email", text: "d.kulkarni@example.com" },
        { type: "phone", text: "555-0144" },
        { type: "name",  text: "Marguerite Oyono" },
        { type: "email", text: "m.oyono@example.com" },
        { type: "phone", text: "555-0151" },
        { type: "name",  text: "Anselm Thackeray" },
        { type: "email", text: "a.thackeray@example.com" },
        { type: "phone", text: "555-0166" }
      ]
    },
    {
      # OCR-style line wrap: the phone number is broken mid-value across a line
      # boundary, the way a scanned column sometimes renders.
      id: "v3-st-05", tier: :structural,
      text: <<~TEXT,
        SCANNED — PAGE 3 OF 7

        For account queries the direct line is 555-01
        73 and the reference number should be quoted in full. Calls outside
        listed hours divert to the answering service.
      TEXT
      pii: [
        { type: "phone", text: "555-0173" }
      ]
    },
    {
      # Page-break artifact splits an address across a footer/header boundary.
      id: "v3-st-06", tier: :structural,
      text: <<~TEXT,
        ...forwarding address on file is 1290 Ellersley

        - - - page 4 - - -
        CONFIDENTIAL DRAFT

        Court, Apt 12, Winston-Salem, NC 27101 and should be used for all
        correspondence until further notice.
      TEXT
      pii: [
        { type: "address", text: "1290 Ellersley Court, Apt 12, Winston-Salem, NC 27101" }
      ]
    },
    {
      # Three distinct people packed into one dense paragraph.
      id: "v3-st-07", tier: :structural,
      text: <<~TEXT,
        Handover summary: Cecelia Aubuchon takes the north territory and keeps
        555-0182 as her direct, Ravindra Pillai moves to key accounts and can be
        reached at r.pillai@example.net, and Halvard Ottesen covers the remainder
        from the Tulsa office at 4417 Sandpiper Loop, Tulsa, OK 74133 — route
        anything ambiguous to Ravindra first.
      TEXT
      pii: [
        { type: "name",    text: "Cecelia Aubuchon" },
        { type: "phone",   text: "555-0182" },
        { type: "name",    text: "Ravindra Pillai" },
        { type: "email",   text: "r.pillai@example.net" },
        { type: "name",    text: "Halvard Ottesen" },
        { type: "address", text: "4417 Sandpiper Loop, Tulsa, OK 74133" }
      ]
    },
    {
      # Multi-type run-on #1: name + phone + email in a single sentence.
      id: "v3-st-08", tier: :structural,
      text: <<~TEXT,
        just grab Perpetua Vandersloot on 555-0193 or if she doesnt pick up try
        p.vandersloot@example.org shes the only one who can authorise the
        override and the window closes at six so dont leave it
      TEXT
      pii: [
        { type: "name",  text: "Perpetua Vandersloot" },
        { type: "phone", text: "555-0193" },
        { type: "email", text: "p.vandersloot@example.org" }
      ]
    },
    {
      # Multi-type run-on #2: name + address + dob in a single sentence.
      id: "v3-st-09", tier: :structural,
      text: <<~TEXT,
        confirming the file shows Thaddeus Wrenfield at 78 Coldharbour Rise,
        Unit B, Norfolk, VA 23510 born 02/29/1988 which is why the system keeps
        rejecting the date on leap year validation, flagging for manual entry
      TEXT
      pii: [
        { type: "name",    text: "Thaddeus Wrenfield" },
        { type: "address", text: "78 Coldharbour Rise, Unit B, Norfolk, VA 23510" },
        { type: "dob",     text: "02/29/1988" }
      ]
    },
    {
      # CLEAN — structural form, zero PII. Key/value spec sheet full of
      # number-ish decoys: part codes, dimensions, tolerances, a date.
      id: "v3-st-10", tier: :structural, clean: true,
      text: <<~TEXT,
        COMPONENT SPEC — REV 4

        Part number:    HX-4471-B
        Material:       6061-T6 aluminium
        Bore:           12.70 mm
        Tolerance:      +/- 0.05 mm
        Finish:         anodised, clear
        Revision date:  03/11/2024
        Supersedes:     REV 3, withdrawn
      TEXT
      pii: []
    },

    # ─────────────────────────── ADVERSARIAL ───────────────────────────
    {
      # Given name is also a common noun, used in a sentence where "hope" would
      # read naturally as the noun. False-negative risk.
      id: "v3-ad-01", tier: :adversarial,
      text: <<~TEXT,
        There is not much hope of finishing before Friday, but Hope Adeyemi says
        the second crew can start Monday if the permit clears. She will confirm
        either way by end of day.
      TEXT
      pii: [
        { type: "name", text: "Hope Adeyemi" }
      ]
    },
    {
      # Given name is a place name, in a document that also mentions real places.
      id: "v3-ad-02", tier: :adversarial,
      text: <<~TEXT,
        The Paris office is closed for the holiday, so Paris Nkemdirim is working
        out of Lyon this week instead. Anything urgent for the France accounts
        should go through her rather than the general inbox.
      TEXT
      pii: [
        { type: "name", text: "Paris Nkemdirim" }
      ]
    },
    {
      # Surname is a common word, in a sentence dense with that word's other sense.
      id: "v3-ad-03", tier: :adversarial,
      text: <<~TEXT,
        We surveyed the north field twice and the field notes still disagree with
        the plan. Bartholomew Field signed off on the original survey, so he is
        the one to ask before we re-stake anything.
      TEXT
      pii: [
        { type: "name", text: "Bartholomew Field" }
      ]
    },
    {
      # CLEAN — redaction-flavoured decoy. Looks like PII is about to appear and
      # never does: masked runs, an empty "my" possessive, a stripped signature.
      id: "v3-ad-04", tier: :adversarial, clean: true,
      text: <<~TEXT,
        Per policy I have removed the identifying details before forwarding.

        Reporting party: [REDACTED]
        Contact on file: ***-****
        Address of record: ██████████

        please don't share my ***

        Everything else in the report stands as written.

        --
        [signature removed]
      TEXT
      pii: []
    },
    {
      # CLEAN — an empty labelled form. Every PII label present, no values.
      id: "v3-ad-05", tier: :adversarial, clean: true,
      text: <<~TEXT,
        NEW ACCOUNT FORM — TEMPLATE (do not complete, sample only)

        Full name:
        Date of birth:
        Social security number:
        Email address:
        Telephone:
        Mailing address:

        Return the completed form to your branch, not by email.
      TEXT
      pii: []
    },
    {
      # CLEAN — project and product codenames that read like person names.
      id: "v3-ad-06", tier: :adversarial, clean: true,
      text: <<~TEXT,
        STATUS — internal

        Project Wolfram Hale remains blocked on the vendor.
        Ranger Mills is now merged into the same track.
        Baker Douglas ships first, ahead of Ranger Mills.

        All three are codenames, not customers — please stop asking procurement
        to invoice them.
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
    documents: DocumentsV3.all.size,
    by_tier: DocumentsV3.all.group_by { it[:tier] }.transform_values(&:size),
    clean_documents: DocumentsV3.clean.map { it[:id] },
    ground_truth_items: DocumentsV3.ground_truth_count,
    by_type: DocumentsV3.all.flat_map { it[:pii] }.group_by { it[:type] }.transform_values(&:size)
  )
end
