// IMPORTS ------------------------------------------------

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// MAIN    ------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL   ------------------------------------------------

type Model {
  Model(
    answers: Answers,
    next_questions: List(Question),
    previous_questions: List(Question),
    current_page: Page,
    field_content: Option(String),
    result: Option(Frequency),
  )
}

type Answers =
  List(Choice)

type Frequency {
  Frequency(
    freq: Station,
    name: String,
    adjectives: List(String),
    tags: List(String),
    playlist: String,
  )
}

type Question {
  Question(question: String, choices: List(Choice))
}

type Choice {
  PromptChoice(answer: String, station: Station)
  CustomChoice(text: String)
}

type Station {
  Slower
  Slow
  Fast
  Faster
}

type Page {
  Home
  Prompt(question: Question)
  LoadingResult
  Result
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model: Model =
    Model(
      // answers: [],
      answers: [
        PromptChoice(
          answer: "Une joie simple, ancrée, je danse comme je respire",
          station: Slower,
        ),
        PromptChoice(
          answer: "Une joie simple, ancrée, je danse comme je respire",
          station: Slower,
        ),
        PromptChoice(
          answer: "Une joie simple, ancrée, je danse comme je respire",
          station: Slower,
        ),
      ],
      next_questions: list.shuffle(questions),
      previous_questions: [],
      current_page: Home,
      field_content: None,
      result: Some(Frequency(
        freq: Faster,
        name: "Hard Speed Radio",
        adjectives: ["électrisante", "haletante"],
        tags: ["kick sec", "grosse tabasse"],
        playlist: "https://link.deezer.com/s/30iKS8WFIDokwCdWfihFA",
      )),
    )

  #(model, effect.none())
}

// UPDATE  ------------------------------------------------

type Msg {
  StartQuizz
  NextQuestion(choice: Option(Choice))
  PreviousQuestion
  ChangeField(String)
  FetchResults(answers: Answers)
  StartOver
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    StartOver -> init(Nil)
    StartQuizz -> {
      let assert [next_question, ..rest] = model.next_questions
      #(
        Model(
          ..model,
          current_page: Prompt(next_question),
          next_questions: rest,
          previous_questions: [],
        ),
        effect.none(),
      )
    }
    NextQuestion(None) -> {
      #(model, effect.none())
    }
    NextQuestion(Some(previous_choice)) ->
      case model.current_page, model.next_questions {
        Prompt(current_quesetion), [next_question, ..rest] -> #(
          Model(
            ..model,
            answers: [previous_choice, ..model.answers],
            next_questions: rest,
            previous_questions: [current_quesetion, ..model.previous_questions],
            field_content: None,
            current_page: Prompt(next_question),
          ),
          effect.none(),
        )
        _, [] -> #(
          Model(
            ..model,
            answers: [previous_choice, ..model.answers],
            current_page: LoadingResult,
          ),
          effect.none(),
          // Here we'll call the API to fetch the results
        )
        Home, _ | LoadingResult, _ | Result, _ -> #(model, effect.none())
      }
    PreviousQuestion -> {
      let assert Prompt(current_question) = model.current_page
      case model.previous_questions, model.answers {
        [previous_question, ..rest], [previous_answer, ..answers] -> #(
          Model(
            ..model,
            current_page: Prompt(previous_question),
            previous_questions: rest,
            next_questions: [current_question, ..model.next_questions],
            field_content: case previous_answer {
              CustomChoice(text) -> Some(text)
              _ -> None
            },
            answers: answers,
          ),
          effect.none(),
        )
        _, _ -> #(model, effect.none())
        // Either 1st question or out of bounds
      }
    }
    ChangeField(text) -> #(
      Model(..model, field_content: case text {
        "" -> None
        _ -> Some(text)
      }),
      effect.none(),
    )
    FetchResults(answers) -> todo
  }
}

// VIEW    ------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let total_questions = list.length(questions)
  let current_question = list.length(model.previous_questions) + 1
  case model {
    Model(current_page: Home, ..) -> view_home()
    Model(current_page: Prompt(question), ..) ->
      view_prompt(
        question,
        total_questions,
        current_question,
        model.field_content,
      )
    Model(current_page: LoadingResult, ..) -> view_loading()
    Model(current_page: Result, ..) -> view_result(model.result)
  }
}

fn view_hero(content: List(Element(Msg))) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "@container hero size-full min-h-screen min-w-screen bg-(image:--duotone-gradient)",
      ),
    ],
    [
      view_header(),
      html.div(
        [
          attribute.class(
            "size-full bg-[url(/src/assets/noise.svg)] mix-blend-soft-light opacity-50 contrast-150",
          ),
        ],
        [],
      ),
      html.div(
        [
          attribute.class(
            "hero-content flex-col gap-2 mt-4 @4xl:gap-7 text-neutral-content text-center",
          ),
        ],
        content,
      ),
      view_footer(),
    ],
  )
}

fn view_home() -> Element(Msg) {
  view_hero([
    html.h1(
      [
        attribute.class(
          "mb-2 p-4 pt-1 text-3xl "
          <> "@lg:mb-4 @lg:p-8 @lg:pt-3 @lg:text-5xl "
          <> "@4xl:mb-5 @4xl:p-12 @4xl:pt-5 @4xl:text-7xl "
          <> "size-fit text-neutral font-normal italic font-obviously tracking-[-.12em]",
        ),
        attribute.style("background", "white"),
      ],
      [html.text("scanne ta fréquence")],
    ),
    html.p(
      [
        attribute.class(
          "w-2xs px-3 text-sm "
          <> "@lg:w-md @lg:px-5 @lg:text-lg "
          <> "@4xl:w-xl @lg:px-6 @4xl:text-xl "
          <> "font-normal text-base-content font-darker",
        ),
      ],
      [
        html.strong([], [
          html.text("Réponds au test pour savoir quelle onde vibre en toi. "),
        ]),
        html.text(
          "À la fin, on t'attribue une station ...et la vibe qui va avec.",
        ),
      ],
    ),
    html.button(
      [
        attribute.class(
          "btn btn-sm btn-primary rounded-none w-fit m-4 pb-1 "
          <> "@lg:btn-md @4xl:btn-xl "
          <> "font-darker "
          <> "text-xl @lg:text-2xl @4xl:text-3xl",
        ),
        event.on_click(StartQuizz),
      ],
      [html.text("Démarrer le test")],
    ),
  ])
}

fn view_header() -> Element(Msg) {
  html.header(
    [
      attribute.class(
        "flex flex-row h-24 w-full bg-repeat-x place-self-start bg-[url(/src/assets/dashed-line-top.svg)]",
      ),
    ],
    [],
  )
}

fn view_footer() -> Element(Msg) {
  html.footer([attribute.class("footer place-self-end place-items-end gap-0")], [
    view_logos(),
    html.img([
      attribute.class("w-full h-4 @4xl:h-fit object-cover"),
      attribute.src("/src/assets/dashed-line-bottom.svg"),
    ]),
  ])
}

fn view_logos() -> Element(Msg) {
  html.img([
    attribute.class("h-1/2 @lg:portrait:h-3/4 @4xl:h-auto"),
    attribute.src("/src/assets/logos.svg"),
  ])
}

fn view_prompt(
  question: Question,
  total_questions: Int,
  question_number: Int,
  field_content: Option(String),
) -> Element(Msg) {
  view_hero([
    view_step_indicator(total_questions, question_number),
    html.h1(
      [
        attribute.class(
          "p-2 text-2xl "
          <> "@lg:text-3xl "
          <> "@4xl:text-5xl "
          <> "text-neutral font-normal italic font-obviously tracking-[-.08em]",
        ),
      ],
      [html.text(question.question)],
    ),
    view_field_nav(total_questions, question_number, field_content),
    question.choices |> view_choices,
  ])
}

fn view_step_indicator(total_steps: Int, current_step: Int) -> Element(Msg) {
  let steps = list.range(1, total_steps)
  html.ul(
    [
      attribute.class(
        "steps text-center text-neutral font-semibold font-darker text-xl",
      ),
    ],
    list.map(steps, fn(step) {
      html.li(
        [
          attribute.class(
            "step"
            <> case step <= current_step {
              True -> " step-primary"
              False -> ""
            },
          ),
        ],
        [
          html.span([attribute.class("pb-1 step-icon place-content-center")], [
            step |> int.to_string |> html.text,
          ]),
        ],
      )
    }),
  )
}

fn view_choices(choices: List(Choice)) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex flex-col place-items-center gap-2 w-full my-6 @lg:landscape:my-1 "
        <> "@lg:w-3xl @4xl:w-4xl",
      ),
    ],
    [
      html.p([attribute.class("font-darker pb-1 @lg:text-xl")], [
        html.text("En manque d'inspi ?"),
      ]),
      html.div(
        [
          attribute.class(
            "flex flex-wrap place-content-center "
            <> "place-items-center gap-2 font-darker",
          ),
        ],
        list.map(choices, view_choice_button),
      ),
    ],
  )
}

fn view_choice_button(choice: Choice) -> Element(Msg) {
  let assert PromptChoice(answer, _) = choice
  html.button(
    [
      attribute.class(
        "btn btn-soft btn-xs "
        <> "px-5 pb-1 "
        <> "opacity-50 shadow-none "
        <> "transition "
        <> "text-sm @lg:text-lg "
        <> "hover:opacity-90 hover:shadow-(color:--color-primary) "
        <> "active:shadow-md active:shadow-(color:--color-primary) active:opacity-100",
      ),
      event.on_click(NextQuestion(Some(choice))),
    ],
    [html.text(answer |> string.split(", ") |> list.first |> result.unwrap(""))],
  )
}

fn view_field_nav(
  total_steps: Int,
  current_step: Int,
  field_content: Option(String),
) -> Element(Msg) {
  html.div([attribute.class("flex flex-row w-full place-items-center gap-2")], [
    html.button(
      [
        attribute.class("btn btn-circle btn-sm @lg:btn-md @4xl:btn-lg"),
        attribute.hidden(current_step == 1),
        event.on_click(PreviousQuestion),
      ],
      [html.text("←")],
    ),
    html.label(
      [
        attribute.class(
          "input input-md rounded-full @lg:input-lg @4xl:input-xl "
          <> "w-full "
          <> "font-darker "
          <> "text-xl @lg:text-2xl @4xl:text-3xl "
          <> "text-base-content font-medium",
        ),
      ],
      [
        html.input([
          attribute.class("grow pb-1 pl-3"),
          attribute.type_("text"),
          attribute.placeholder("Écris ta réponse"),
          event.on_input(ChangeField),
          attribute.value(field_content |> option.unwrap("")),
        ]),
        html.button(
          [
            attribute.class(
              "btn btn-circle btn-primary btn-xs @lg:btn-sm @4xl:btn-md @lg:text-md @4xl:text-lg font-sans",
            ),
            attribute.disabled(option.is_none(field_content)),
            event.on_click(
              NextQuestion(Some(CustomChoice(option.unwrap(field_content, "")))),
            ),
          ],
          [
            html.text(case current_step == total_steps {
              True -> "✓"
              False -> "→"
            }),
          ],
        ),
      ],
    ),
  ])
}

fn view_loading() -> Element(Msg) {
  html.div([attribute.class("hero min-h-screen")], [
    html.div(
      [
        attribute.class(
          "size-full animate-scroll-down bg-(image:--loading-gradient)",
        ),
        attribute.style(
          "animation-delay",
          "-" <> int.random(60) |> int.to_string <> "s",
        ),
        attribute.style("background-size", "100% 200%"),
      ],
      [
        html.div(
          [
            attribute.class("size-full"),
            attribute.style("background", "url(./src/assets/noise.svg)"),
            attribute.style("mix-blend-mode", "screen"),
            attribute.style("opacity", ".2"),
            attribute.style("filter", "contrast(1.5)"),
          ],
          [],
        ),
      ],
    ),
    html.div([attribute.class("hero-overlay animate-pulse-darken")], []),
    html.div([attribute.class("hero-content text-center")], [
      html.h1(
        [
          attribute.class(
            "text-5xl text-neutral-content font-light italic font-obviously tracking-[-.08em] animate-pulse",
          ),
        ],
        [html.text("calcul de ta fréquence ...")],
      ),
    ]),
  ])
}

fn view_result(result: Option(Frequency)) -> Element(Msg) {
  todo
}

fn view_answers(answers: Answers) -> Element(Msg) {
  html.div(
    [],
    list.map(answers, fn(choice) {
      html.section([attribute.class("text-neutral-content")], case choice {
        PromptChoice(answer, station) -> [
          html.p([], [html.text(answer)]),
          html.p([], [station |> station_to_string |> html.text]),
        ]
        CustomChoice(text) -> [html.p([], [html.text(text)])]
      })
    }),
  )
}

// DATA    ------------------------------------------------

const questions: List(Question) = [
  Question(
    question: "Un lieu idéal pour écouter de la musique ?",
    choices: [
      PromptChoice(
        answer: "En plein air, au coucher du soleil 🌞",
        station: Slower,
      ),
      PromptChoice(
        answer: "Un rooftop cosy, avec lumières chaudes 🧡",
        station: Slow,
      ),
      PromptChoice(
        answer: "Un sous-sol moite, sombre et un systeme son bien calé 🏭",
        station: Fast,
      ),
      PromptChoice(
        answer: "Une friche industrielle, avec un maxi mur de son 🏚️",
        station: Faster,
      ),
    ],
  ),
  Question(
    question: "Ton tempo intérieur ce soir ?",
    choices: [
      PromptChoice(
        answer: "Smooth, envie de danser en discutant",
        station: Slower,
      ),
      PromptChoice(
        answer: "Flottant et groovy, je me laisse porter par la mélodie",
        station: Slow,
      ),
      PromptChoice(
        answer: "Soutenu, il faut que je me dépense au rythme du son",
        station: Fast,
      ),
      PromptChoice(answer: "Rapide, j’ai besoin que ça galope", station: Faster),
    ],
  ),
  Question(
    question: "Quel lien tu cherches avec les gens ?",
    choices: [
      PromptChoice(
        answer: "Danser ensemble, comme une jam session",
        station: Slower,
      ),
      PromptChoice(
        answer: "Partager des regards, des sourires, sans parler",
        station: Slow,
      ),
      PromptChoice(answer: "Me perdre dans la masse, en rythme", station: Fast),
      PromptChoice(
        answer: "Être seul·e dans ma bulle, en transe",
        station: Faster,
      ),
    ],
  ),
  Question(
    question: "Si tu devais choisir un détail dans la musique…",
    choices: [
      PromptChoice(
        answer: "Une basse funky, une voix attachante",
        station: Slower,
      ),
      PromptChoice(
        answer: "Des percussions organiques, une mélodie puissante",
        station: Slow,
      ),
      PromptChoice(
        answer: "Un ostinato entêtant, des synthés abstraits",
        station: Fast,
      ),
      PromptChoice(
        answer: "Un rythme extatique, des synthés comme des lasers",
        station: Faster,
      ),
    ],
  ),
  Question(
    question: "Qu’est-ce qui t’habite quand tu bouges ?",
    choices: [
      PromptChoice(
        answer: "Une joie simple ancrée, je danse comme je respire",
        station: Slower,
      ),
      PromptChoice(
        answer: "Une ivresse douce, entre imaginaire et mouvement",
        station: Slow,
      ),
      PromptChoice(
        answer: "Une tension libérée, je tape du pied en rythme",
        station: Fast,
      ),
      PromptChoice(
        answer: "Une transe étrange, presque mystique",
        station: Faster,
      ),
    ],
  ),
]

fn station_to_string(station: Station) -> String {
  case station {
    Faster -> "108.9 FM"
    Fast -> "105.6 FM"
    Slow -> "101.1 FM"
    Slower -> "97.3 FM"
  }
}
