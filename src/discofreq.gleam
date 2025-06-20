// IMPORTS ------------------------------------------------

import gleam/int
import gleam/list
import gleam/option.{type Option, None}
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
    user_path: List(Question),
    current_page: Page,
    result: Option(Result),
  )
}

type Answers =
  List(Choice)

type Result =
  #(Station, String)

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
      answers: [],
      user_path: list.shuffle(questions),
      current_page: Home,
      result: None,
    )

  #(model, effect.none())
}

// UPDATE  ------------------------------------------------

type Msg {
  StartQuizz
  NextQuestion(choice: Choice)
  StartOver
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    StartOver -> init(Nil)
    StartQuizz -> {
      let assert [next_question, ..rest] = model.user_path
      #(
        Model(..model, current_page: Prompt(next_question), user_path: rest),
        effect.none(),
      )
    }
    NextQuestion(choice) ->
      case model {
        Model(current_page: Home, ..) | Model(current_page: Result, ..) ->
          panic as "Something went very wrong"
        Model(current_page: Prompt(_), user_path: [next, ..rest], ..) -> {
          #(
            Model(
              ..model,
              answers: [choice, ..model.answers],
              user_path: rest,
              current_page: Prompt(next),
            ),
            effect.none(),
          )
        }
        Model(answers: _, user_path: [], ..) -> #(
          Model(..model, current_page: LoadingResult),
          effect.none(),
          // Here we'll call the API to fetch the results
        )
        Model(current_page: LoadingResult, ..) -> #(
          // Once the results are in, we display them to the user
          Model(..model, current_page: Result),
          effect.none(),
        )
      }
  }
}

// VIEW    ------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  case model {
    Model(current_page: Home, ..) -> view_home()
    Model(current_page: Prompt(question), ..) ->
      view_question(
        question,
        list.length(questions) - list.length(model.user_path),
      )
    Model(current_page: LoadingResult, ..) -> view_loading()
    Model(current_page: Result, ..) -> view_result()
  }
}

fn view_home() -> Element(Msg) {
  html.div(
    [
      attribute.class("hero min-h-screen"),
      attribute.style(
        "background",
        "linear-gradient(179.99deg, #C0B2B2 3.8%, #FF8635 26.35%, #C0B2B2 56.23%, #B991FE 104.99%)",
      ),
    ],
    [
      html.div([attribute.class("hero-overlay")], []),
      html.div(
        [attribute.class("hero-content text-neutral-content text-center")],
        [
          html.div([attribute.class("max-w-2xl")], [
            html.h1(
              [
                attribute.class("mb-5 p-5 pb-7 text-7xl text-neutral font-bold"),
                attribute.style("background", "white"),
              ],
              [html.text("Scan ta frequence")],
            ),
            html.p([attribute.class("mb-5 text-lg")], [
              html.text(
                "Réponds au test pour savoir quelle onde vibre en toi. À la fin, on t'attribue une station ...et la vibe qui va avec.",
              ),
            ]),
            html.button(
              [attribute.class("btn rounded-none btn-lg btn-primary m-4 px-12"), event.on_click(StartQuizz)],
              [html.text("C'est parti !")],
            ),
          ]),
        ],
      ),
    ],
  )
}

fn view_question(question: Question, question_number: Int) -> Element(Msg) {
  html.div(
    [
      attribute.class("hero min-h-screen"),
      attribute.style(
        "background",
        "linear-gradient(179.99deg, #C0B2B2 3.8%, #FF8635 26.35%, #C0B2B2 56.23%, #B991FE 104.99%)",
      ),
    ],
    [
      html.div([attribute.class("hero-content text-neutral text-center")], [
        html.div([attribute.class("max-w-4xl")], [
          html.p([attribute.class("mb-3 font-bold")], [
            html.text("Question " <> int.to_string(question_number)),
          ]),
          html.h1([attribute.class("mb-5 p-2 text-3xl font-bold")], [
            html.text(question.question),
          ]),
          html.div(
            [attribute.class("grid grid-cols-2 gap-2")],
            list.map(question.choices, view_choice_button),
          ),
        ]),
      ]),
    ],
  )
}

fn view_choice_button(choice: Choice) -> Element(Msg) {
  html.button(
    [
      attribute.class("btn rounded-none btn-primary-content"),
      event.on_click(NextQuestion(choice)),
    ],
    [html.text(choice.answer)],
  )
}

fn view_loading() -> Element(Msg) {
  html.div(
    [
      attribute.class("hero min-h-screen"),
      attribute.style(
        "background",
        "linear-gradient(179.99deg, #C6B7B8 2.9%, #FE9722 4.54%, #C6B7B8 12.25%, #000000 18.83%, #B68CFE 22.65%, #000000 54.66%, #C6B7B8 71.96%, #C6B7B8 77.73%, #FE9722 80.35%, #C6B7B8 89.81%, #FE9722 104.99%, #C6B7B8 2.9%, #FE9722 9.04%, #C6B7B8 24.25%, #000000 36.83%, #B68CFE 43.65%, #000000 54.66%, #C6B7B8 71.96%, #C6B7B8 77.73%, #FE9722 80.35%, #C6B7B8 89.81%, #FE9722 104.99%)"
      ),
    ],
    [
      html.div([attribute.class("hero-overlay")], []),
      html.div(
        [attribute.class("hero-content text-center")],
        [
          html.div([attribute.class("max-w-5xl")], [
            html.h1(
              [
                attribute.class("text-3xl text-neutral-content"),
              ],
              [html.text("calcul de ta fréquence ...")],
            ),
          ]),
        ],
      ),
    ],
  )
}

fn view_result() -> Element(Msg) {
    todo
}

// DATA    ------------------------------------------------

const questions: List(Question) = [
  Question(
    question: "Un lieu idéal pour écouter de la musique ?",
    choices: [
      Choice(answer: "En open-air au coucher du soleil 🌞", station: Slower),
      Choice(
        answer: "Dans un club cosy avec lumières chaudes 🧡",
        station: Slow,
      ),
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
