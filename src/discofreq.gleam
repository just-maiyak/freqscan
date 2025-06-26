// IMPORTS ------------------------------------------------

import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
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
    result: Option(Frequency),
  )
}

type Answers =
  List(Choice)

type Frequency {
  Frequency(freq: Station, name: String, adjectives: List(String), tags: List(String), playlist: String)
}

type Question {
  Question(question: String, choices: List(Choice))
}

type Choice {
  Choice(answer: String, station: Station)
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
        Choice(
          answer: "Une joie simple, ancrée, je danse comme je respire",
          station: Slower,
        ),
        Choice(
          answer: "Une joie simple, ancrée, je danse comme je respire",
          station: Slower,
        ),
        Choice(
          answer: "Une joie simple, ancrée, je danse comme je respire",
          station: Slower,
        ),
      ],
      next_questions: list.shuffle(questions),
      previous_questions: [],
      current_page: Home,
      result: Some(Frequency(freq: Faster, name: "Hard Speed Radio", adjectives: ["électrisante", "haletante"], tags: ["kick sec", "grosse tabasse"], playlist: "https://link.deezer.com/s/30iKS8WFIDokwCdWfihFA")),
    )

  #(model, effect.none())
}

// UPDATE  ------------------------------------------------

type Msg {
  StartQuizz
  NextQuestion(choice: Choice)
  PreviousQuestion
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
    NextQuestion(previous_choice) ->
      case model.current_page, model.next_questions {
        Prompt(current_quesetion), [next_question, ..rest] -> #(
          Model(
            ..model,
            answers: [previous_choice, ..model.answers],
            next_questions: rest,
            previous_questions: [current_quesetion, ..model.previous_questions],
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
        [previous_question, ..rest], [_, ..answers] -> #(
          Model(
            ..model,
            current_page: Prompt(previous_question),
            previous_questions: rest,
            next_questions: [current_question, ..model.next_questions],
            answers: answers,
          ),
          effect.none(),
        )
        _, _ -> #(model, effect.none())
        // Either 1st question or out of bounds
      }
    }
    FetchResults(answers) -> todo
  }
}

// VIEW    ------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  case model {
    Model(current_page: Home, ..) -> view_home()
    Model(current_page: Prompt(question), ..) ->
      view_question(
        question,
        list.length(questions) - list.length(model.next_questions),
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
            "hero-content size-fit flex-col gap-2 mt-4 @4xl:gap-7 text-neutral-content text-center",
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
          <> "font-normal text-base-content font-helvetica-neue",
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
          "btn btn-sm "
          <> "@lg:btn-md "
          <> "@4xl:btn-xl "
          <> "btn-primary w-fit m-4 font-helvetica-neue",
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
        "flex flex-row w-full bg-repeat-x place-self-start bg-[url(/src/assets/dashed-line-top.svg)]",
      ),
    ],
    [
      html.label([attribute.class(" p-8 swap swap-rotate z-20 ")], [
        html.input([
          attribute.type_("checkbox"),
          attribute.class("theme-controller"),
          attribute.value("station-r-light"),
        ]),
        html.img([
          attribute.class("swap-on h-10 w-10 fill-current"),
          attribute.src("./src/assets/sun.svg"),
        ]),
        html.img([
          attribute.class("swap-off h-10 w-10 fill-current"),
          attribute.src("./src/assets/moon.svg"),
        ]),
      ]),
    ],
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
    attribute.src("./src/assets/logos.svg"),
  ])
}

fn view_question(question: Question, question_number: Int) -> Element(Msg) {
  view_hero([
    html.p(
      [
        attribute.class(
          "w-fit px-4 pb-1 text-md "
          <> "@lg:text-lg "
          <> "@4xl:text-2xl "
          <> "justify-self-center text-neutral font-semibold font-darker rounded-4xl bg-primary",
        ),
      ],
      [html.text("Question " <> int.to_string(question_number))],
    ),
    html.h1(
      [
        attribute.class(
          "mb-4 p-2 text-2xl "
          <> "@lg:text-3xl "
          <> "@4xl:text-5xl "
          <> "text-neutral font-normal italic font-obviously tracking-[-.08em]",
        ),
      ],
      [html.text(question.question)],
    ),
    html.div(
      [
        attribute.class(
          "max-w-2xs "
          <> "portrait:flex portrait:flex-col "
          <> "landscape:grid landscape:grid-cols-2 landscape:content-center "
          <> "@lg:max-w-none h-max place-items-center gap-2",
        ),
      ],
      list.map(list.shuffle(question.choices), view_choice_button),
    ),
    html.button([attribute.class("btn"), event.on_click(PreviousQuestion)], [
      html.text("Précédent"),
    ]),
  ])
}

fn view_choice_button(choice: Choice) -> Element(Msg) {
  html.button(
    [
      attribute.class(
        "btn btn-sm @lg:portrait:btn-md @4xl:btn-lg rounded-3xl h-lg px-5",
      ),
      event.on_click(NextQuestion(choice)),
    ],
    [html.text(choice.answer)],
  )
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
      html.section([attribute.class("text-neutral-content")], [
        html.p([], [html.text(choice.answer)]),
        html.p([], [choice.station |> station_to_string |> html.text]),
      ])
    }),
  )
}

// DATA    ------------------------------------------------

const questions: List(Question) = [
  Question(
    question: "Un lieu idéal pour écouter de la musique ?",
    choices: [
      Choice(answer: "En open-air au coucher du soleil 🌞", station: Slower),
      Choice(answer: "Dans un club cosy avec lumières chaudes 🧡", station: Slow),
      Choice(
        answer: "Un club sombre avec strobos et système son massif 🏭",
        station: Fast,
      ),
      Choice(
        answer: "Une friche industrielle, avec un sound system brut 🏚️",
        station: Faster,
      ),
    ],
  ),
  Question(
    question: "Ton tempo intérieur ce soir ?",
    choices: [
      Choice(answer: "Smooth, envie de danser en discutant", station: Slower),
      Choice(
        answer: "Flottant et groovy en me laissant porter par la mélodie",
        station: Slow,
      ),
      Choice(
        answer: "Il faut que je me dépense au rythme du son",
        station: Fast,
      ),
      Choice(answer: "Rapide, j’ai besoin que ça galope", station: Faster),
    ],
  ),
  Question(
    question: "Quel lien tu cherches avec les gens ?",
    choices: [
      Choice(answer: "Danser ensemble, comme une jam session", station: Slower),
      Choice(
        answer: "Partager des regards, des sourires, sans parler",
        station: Slow,
      ),
      Choice(answer: "Me perdre dans la masse, en rythme", station: Fast),
      Choice(answer: "Être seul·e dans ma bulle, en transe", station: Faster),
    ],
  ),
  Question(
    question: "Si tu devais choisir un détail dans la musique…",
    choices: [
      Choice(
        answer: "Une basse funky et des percussions organiques",
        station: Slower,
      ),
      Choice(
        answer: "Une nappe aérienne et une mélodie entêtante",
        station: Slow,
      ),
      Choice(
        answer: "Un rythme qui se répète et progresse lentement",
        station: Fast,
      ),
      Choice(answer: "Un kick sec et rapide, qui martelle", station: Faster),
    ],
  ),
  Question(
    question: "Qu’est-ce qui t’habite quand tu bouges ?",
    choices: [
      Choice(
        answer: "Une joie simple, ancrée, je danse comme je respire",
        station: Slower,
      ),
      Choice(
        answer: "Une ivresse douce, entre imaginaire et mouvement",
        station: Slow,
      ),
      Choice(
        answer: "Une tension libérée, je tape du pied en rythme",
        station: Fast,
      ),
      Choice(answer: "Une transe étrange, presque mystique", station: Faster),
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
