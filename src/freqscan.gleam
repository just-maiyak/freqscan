// IMPORTS ------------------------------------------------

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json
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
import rsvp

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
    next_questions: List(#(Question, Answers)),
    previous_questions: List(#(Question, Answers)),
    current_page: Page,
    field_content: Option(String),
    result: Option(Frequency),
  )
}

type Answers =
  List(Choice)

type Playlist {
  Playlist(deezer: String, spotify: String, apple: String, youtube: String)
}

type Frequency {
  Frequency(
    frequency: Station,
    name: String,
    verbatims: List(String),
    tags: List(String),
    artists: List(String),
    playlist: Playlist,
  )
}

fn dummy_result() {
  Frequency(
    frequency: Fast,
    name: "Test Test Radio",
    verbatims: ["Lorem Ipsum", "Dolor Sit Amet", "Consectetur Adipiscing Elit"],
    tags: ["Etheré", "Doux", "Calme", "Paisible"],
    artists: ["Alex Kassian", "Asphalt DJ", "Paramida"],
    playlist: Playlist(deezer: "", spotify: "", apple: "", youtube: ""),
  )
}

type Questionnaire {
  Questionnaire(questions: List(#(Question, Answers)))
}

type Question {
  Question(question_id: String, question: String)
}

type Choice {
  PromptChoice(answer: String, station: Station)
  CustomChoice(question: Question, answer: String)
}

type Station {
  Slower
  Slow
  Fast
  Faster
}

type Page {
  Home
  Prompt(question: Question, choices: Answers)
  LoadingResult
  Result
}

fn init(_) -> #(Model, Effect(Msg)) {
  let questionnaire: Questionnaire = Questionnaire(questions:)
  let model: Model =
    Model(
      answers: [],
      next_questions: list.shuffle(questionnaire.questions),
      previous_questions: [],
      current_page: Home,
      field_content: None,
      result: None,
    )

  #(model, effect.none())
}

fn choice_to_json(choice: Choice) -> json.Json {
  case choice {
    CustomChoice(question:, answer:) ->
      json.object([
        #("question_id", json.string(question.question_id)),
        #("answer", json.string(answer)),
      ])
    _ -> json.int(1)
  }
}

fn fetch_frequency(
  answers: List(Choice),
  language: String,
  on_response handle_response: fn(Result(Frequency, rsvp.Error)) -> Msg,
) -> Effect(Msg) {
  let url = "http://localhost:8000/predict?language=" <> language
  let decoder = frequency_decoder()
  let handler = rsvp.expect_json(decoder, handle_response)
  let body =
    json.object([#("answers", json.array(answers, of: choice_to_json))])

  rsvp.post(url, body, handler)
}

fn station_decoder() -> Decoder(Station) {
  use freq_string <- decode.then(decode.string)
  case freq_string {
    "slower" -> decode.success(Slower)
    "slow" -> decode.success(Slow)
    "fast" -> decode.success(Fast)
    "faster" -> decode.success(Faster)
    _ -> decode.failure(Fast, "Could not parse frequency")
  }
}

fn playlist_decoder() -> Decoder(Playlist) {
  use deezer <- decode.field("deezer", decode.string)
  use spotify <- decode.field("spotify", decode.string)
  use apple <- decode.field("apple", decode.string)
  use youtube <- decode.field("youtube", decode.string)

  decode.success(Playlist(deezer:, spotify:, apple:, youtube:))
}

fn frequency_decoder() -> Decoder(Frequency) {
  use frequency <- decode.field("frequency", station_decoder())
  use name <- decode.field("name", decode.string)
  use verbatims <- decode.field("verbatims", decode.list(decode.string))
  use tags <- decode.field("tags", decode.list(decode.string))
  use artists <- decode.field("artists", decode.list(decode.string))
  use playlist <- decode.field("playlist", playlist_decoder())

  decode.success(Frequency(
    frequency:,
    name:,
    verbatims:,
    tags:,
    artists:,
    playlist:,
  ))
}

// UPDATE  ------------------------------------------------

type Msg {
  StartQuizz
  NextQuestion(choice: Option(Choice))
  PreviousQuestion
  ChangeField(String)
  GotResults(Result(Frequency, rsvp.Error))
  StartOver
  NoOp
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    StartOver -> init(Nil)
    StartQuizz -> {
      let assert [#(question, choices), ..rest] = model.next_questions
      #(
        Model(
          ..model,
          current_page: Prompt(question:, choices:),
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
        Prompt(question:, choices:), [#(next_question, next_choices), ..rest] -> #(
          Model(
            ..model,
            answers: [previous_choice, ..model.answers],
            next_questions: rest,
            previous_questions: [
              #(question, choices),
              ..model.previous_questions
            ],
            field_content: None,
            current_page: Prompt(question: next_question, choices: next_choices),
          ),
          effect.none(),
        )
        _, [] -> #(
          Model(
            ..model,
            answers: [previous_choice, ..model.answers],
            current_page: LoadingResult,
          ),
          fetch_frequency(model.answers, "en", GotResults),
          // Here we'll call the API to fetch the results
        )
        Home, _ | LoadingResult, _ | Result, _ -> #(model, effect.none())
      }
    PreviousQuestion -> {
      let assert Prompt(question: current_question, choices: current_choices) =
        model.current_page
      case model.previous_questions, model.answers {
        [#(previous_question, previous_choices), ..rest],
          [previous_answer, ..answers]
        -> #(
          Model(
            ..model,
            current_page: Prompt(
              question: previous_question,
              choices: previous_choices,
            ),
            previous_questions: rest,
            next_questions: [
              #(current_question, current_choices),
              ..model.next_questions
            ],
            field_content: case previous_answer {
              CustomChoice(_question, text) -> Some(text)
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
    GotResults(Ok(result)) -> #(
      Model(..model, current_page: Result, result: Some(result)),
      effect.none(),
    )
    GotResults(Error(error)) -> {
      echo error
      #(model, effect.none())
    }
    NoOp -> #(model, effect.none())
  }
}

// VIEW    ------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let total_questions = list.length(questions)
  let current_question = list.length(model.previous_questions) + 1
  case model {
    Model(current_page: Home, ..) -> view_home()
    Model(current_page: Prompt(question, choices), ..) ->
      view_prompt(
        question,
        choices,
        total_questions,
        current_question,
        model.field_content,
      )
    Model(result: None, ..) -> view_loading()
    Model(result: Some(result), ..) -> view_result(result)
  }
}

fn view_hero(
  header: Element(Msg),
  content: List(Element(Msg)),
  footer: Element(Msg),
  background: String,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex flex-col "
        <> "w-dvw min-w-xs "
        <> "h-fit min-h-svh "
        <> background,
      ),
    ],
    [
      header,
      html.div([attribute.class("@container hero grow")], [
        html.div([attribute.class("hero-content size-full p-0")], content),
      ]),
      footer,
    ],
  )
}

fn view_home() -> Element(Msg) {
  view_hero(
    view_header(),
    [
      html.div(
        [
          attribute.class(
            "flex flex-col place-items-center py-0 gap-2 @4xl:gap-7 text-neutral-content text-center",
          ),
        ],
        [
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
                html.text(
                  "Réponds au test pour savoir quelle onde vibre en toi. ",
                ),
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
        ],
      ),
    ],
    view_footer(),
    "bg-(image:--duotone-gradient)",
  )
}

fn view_header() -> Element(Msg) {
  html.header(
    [
      attribute.class(
        "flex flex-row place-self-start mobileLandscape:hidden "
        <> "h-24 w-screen "
        <> "bg-repeat-x bg-[url(/src/assets/dashed-line-top.svg)]",
      ),
    ],
    [],
  )
}

fn view_result_header() -> Element(Msg) {
  html.header([attribute.class("flex flex-col place-self-start bg-black")], [
    html.div(
      [
        attribute.class(
          "h-24 w-screen bg-(image:--header-result-gradient) mobileLandscape:hidden",
        ),
      ],
      [],
    ),
    html.div([attribute.class("grow flex flex-row-reverse w-screen")], [
      html.div(
        [
          attribute.class(
            "px-3 pb-2 place-content-center "
            <> "bg-white text-black text-3xl font-light font-obviously",
          ),
        ],
        [
          html.span([attribute.class("mr-1 italic tracking-[-.12em]")], [
            html.text("station"),
          ]),
          html.span([attribute.class("font-bold")], [html.text("R")]),
        ],
      ),
    ]),
  ])
}

fn view_footer() -> Element(Msg) {
  html.footer(
    [
      attribute.class(
        "relative flex flex-col-reverse gap-0 place-content-end mobileLandscape:hidden",
      ),
    ],
    [
      html.img([
        attribute.class("z-1 h-4 lg:h-6 4xl:h-8 w-full object-cover"),
        attribute.src("./src/assets/dashed-line-bottom.svg"),
      ]),
      html.img([
        attribute.class(
          "landscape:absolute landscape:bottom-6 h-18 lg:h-24 place-self-end",
        ),
        attribute.src("./src/assets/logos.svg"),
      ]),
    ],
  )
}

fn view_prompt(
  question: Question,
  choices: Answers,
  total_questions: Int,
  question_number: Int,
  field_content: Option(String),
) -> Element(Msg) {
  view_hero(
    view_header(),
    [
      html.div(
        [
          attribute.class(
            "flex flex-col w-screen py-0 gap-2 @4xl:gap-7 text-neutral-content text-center",
          ),
        ],
        [
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
          view_field_nav(
            total_questions,
            question_number,
            question,
            field_content,
          ),
          choices |> view_choices,
        ],
      ),
    ],
    view_footer(),
    "bg-(image:--duotone-gradient)",
  )
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
        "flex flex-col place-items-center gap-2 my-6 @lg:landscape:my-1",
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
      event.on_click(ChangeField(answer)),
    ],
    [
      html.text(
        answer |> string.split(", ") |> list.first |> result.unwrap("") <> "…",
      ),
    ],
  )
}

fn view_field_nav(
  total_steps: Int,
  current_step: Int,
  current_question: Question,
  field_content: Option(String),
) -> Element(Msg) {
  html.div(
    [attribute.class("flex flex-row w-full place-items-center gap-2 px-4")],
    [
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
            "grow input input-md rounded-full @lg:input-lg @4xl:input-xl "
            <> "font-darker "
            <> "text-xl @lg:text-2xl @4xl:text-3xl "
            <> "text-base-content font-medium",
          ),
        ],
        [
          html.input([
            attribute.class("pb-1 pl-3"),
            attribute.type_("text"),
            attribute.placeholder("Écris ta réponse"),
            event.on_input(ChangeField),
            event.on_keypress(fn(key) {
              case key {
                "Enter" ->
                  NextQuestion(
                    field_content
                    |> option.map(CustomChoice(current_question, _)),
                  )
                _ -> NoOp
              }
            }),
            attribute.value(field_content |> option.unwrap("")),
          ]),
          html.button(
            [
              attribute.class(
                "btn btn-circle btn-primary btn-xs @lg:btn-sm @4xl:btn-md @lg:text-md @4xl:text-lg font-sans",
              ),
              attribute.disabled(option.is_none(field_content)),
              event.on_click(NextQuestion(
                field_content |> option.map(CustomChoice(current_question, _)),
              )),
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
    ],
  )
}

fn view_loading() -> Element(Msg) {
  html.div([attribute.class("hero min-h-svh")], [
    html.div(
      [
        attribute.class(
          "w-svw h-svh min-w-svw min-h-svh animate-scroll-down bg-(image:--loading-gradient)",
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
            attribute.class(
              "h-svh min-h-svh w-full "
              <> "bg-(image:--noise) mix-blend-screen opacity-70",
            ),
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
            "text-5xl text-neutral-content font-light italic font-obviously tracking-[-.08em]",
          ),
        ],
        [html.text("calcul de ta fréquence ...")],
      ),
    ]),
  ])
}

fn view_result(result: Frequency) -> Element(Msg) {
  let background = case result.frequency {
    Slower | Slow -> "bg-(image:--house-result-gradient)"
    Faster | Fast -> "bg-(image:--techno-result-gradient)"
  }
  let pill_color = case result.frequency {
    // Make tailwind preprocessor happy : bg-primary bg-secondary
    Faster | Fast -> "primary"
    Slower | Slow -> "secondary"
  }
  let genre = case result.frequency {
    Slower | Slow -> "House"
    Faster | Fast -> "Techno"
  }
  let location = case result.frequency {
    Slower | Slow -> "à l'Atrium"
    Faster | Fast -> "au Refuge"
  }
  let frequency_pane =
    html.section(
      [
        attribute.class(
          "flex flex-col p-4 landscape:lg:p-24 landscape:lg:pt-8 place-self-stretch "
          <> "shadow-lg/30 "
          <> background
          <> " text-2xl mobileLandscape:text-lg font-darker font-extrabold",
        ),
      ],
      [
        html.h1(
          [
            attribute.class(
              "pb-1 text-neutral-content text-6xl mobileLandscape:text-4xl font-obviously font-normal italic tracking-[-.06em]",
            ),
          ],
          [result.frequency |> station_to_string |> html.text],
        ),
        html.p([attribute.class("h-6 text-neutral-content font-normal")], [
          html.text("Ma fréquence musicale : " <> genre),
        ]),
        html.p([], [
          html.text("Le 31 juillet " <> location <> " de la Rotonde Stalingrad"),
        ]),
        html.h2(
          [
            attribute.class(
              "grow h-[40vh] mobileLandscape:min-h-[20vh] place-content-center "
              <> "text-neutral-content text-6xl mobileLandscape:text-4xl "
              <> "font-obviously font-normal italic tracking-[-.06em]",
            ),
          ],
          [html.text(result.name)],
        ),
        html.div(
          [attribute.class("flex flex-wrap gap-2")],
          {
            use pills, color <- list.map2(
              [result.tags, result.verbatims, result.artists],
              ["bg-neutral-content", "bg-accent", "bg-" <> pill_color],
            )
            use pill <- list.map(pills)
            html.p(
              [
                attribute.class(
                  "pb-1 px-3 "
                  <> color
                  <> " shadow-lg font-bold text-md mobileLandscape:text-sm rounded-3xl",
                ),
              ],
              [html.text(pill)],
            )
          }
            |> list.flatten
            |> list.shuffle,
        ),
      ],
    )
  let cta_pane =
    html.section(
      [
        attribute.class(
          "shrink py-4 mobileLandscape:py-2 px-8 "
          <> "flex flex-col text-center place-items-center place-content-center gap-4 "
          <> "text-2xl mobileLandscape:text-lg/6 font-darker font-extrabold "
          <> "bg-(image:--noise)",
        ),
      ],
      [
        html.p([], [
          html.text(
            "Ce résultat a été conçu entièrement en fonction de tes choix !",
          ),
        ]),
        html.p([attribute.class("font-semibold")], [
          html.text(
            "Nous avons associé tes réponses à des propositions similaires...",
          ),
        ]),
        html.p([], [
          html.text(
            "Viens découvrir l’ambiance qui te correspond  le 31 juillet à la Rotonde avec Éclectique et OD.",
          ),
        ]),
        html.div(
          [
            attribute.class(
              "flex flex-col text-center place-items-center gap-2",
            ),
          ],
          [
            html.button(
              [
                attribute.class(
                  "pb-1 btn btn-"
                  <> pill_color
                  <> " btn-sm mobileLandscape:btn-xs text-xl mobileLandscape:text-lg shadow-lg",
                ),
              ],
              [html.text("Prends ta place")],
            ),
            html.button(
              [
                attribute.class(
                  "pb-1 btn btn-sm mobileLandscape:btn-xs text-xl mobileLandscape:text-lg shadow-lg",
                ),
              ],
              [html.text("Partage ta fréquence")],
            ),
            html.p([], [html.text("Écoute la playlist associée :")]),
            html.div([attribute.class("flex gap-2")], [
              html.button(
                [
                  attribute.class(
                    "place-items-center btn btn-ghost btn-circle btn-sm fa-brands text-xl",
                  ),
                ],
                [
                  html.img([
                    attribute.class("h-6 py-1 transition-all hover:invert"),
                    attribute.src("/src/assets/logos/deezer.svg"),
                  ]),
                ],
              ),
              html.button(
                [
                  attribute.class(
                    "btn btn-ghost btn-circle btn-sm fa-brands fa-spotify text-xl",
                  ),
                ],
                [],
              ),
              html.button(
                [
                  attribute.class(
                    "btn btn-ghost btn-circle btn-sm fa-brands fa-apple text-xl",
                  ),
                ],
                [],
              ),
              html.button(
                [
                  attribute.class(
                    "btn btn-ghost btn-circle btn-sm fa-brands fa-youtube text-xl",
                  ),
                ],
                [],
              ),
            ]),
          ],
        ),
      ],
    )
  html.div(
    [
      attribute.class(
        "flex flex-col " <> "w-dvw min-w-xs " <> "h-full min-h-svh",
      ),
    ],
    [
      view_result_header(),
      html.div(
        [
          attribute.class(
            "grow flex flex-col landscape:flex-row gap-0 text-neutral",
          ),
        ],
        [frequency_pane, cta_pane],
      ),
      view_footer(),
    ],
  )
}

// DATA    ------------------------------------------------

const questions: List(#(Question, Answers)) = [
  #(
    Question(
      question_id: "place",
      question: "Un lieu idéal pour écouter de la musique ?",
    ),
    [
      PromptChoice(
        answer: "En plein air, au coucher du soleil 🌞",
        station: Slower,
      ),
      PromptChoice(
        answer: "Un rooftop cosy, avec lumières chaudes 🧡",
        station: Slow,
      ),
      PromptChoice(
        answer: "Un sous-sol moite, sombre et un systeme son bien réglé 🏭",
        station: Fast,
      ),
      PromptChoice(
        answer: "Une friche industrielle, avec un maxi mur de son 🏚️",
        station: Faster,
      ),
    ],
  ),
  #(
    Question(
      question_id: "spirit",
      question: "Quel est ton tempo intérieur ce soir ?",
    ),
    [
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
  #(
    Question(
      question_id: "outfit",
      question: "Quel lien cherches-tu avec les gens ?",
    ),
    [
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
  #(
    Question(
      question_id: "aesthetic",
      question: "Si tu devais choisir un détail dans la musique…",
    ),
    [
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
  #(
    Question(
      question_id: "fuel",
      question: "Qu’est-ce qui t’habite quand tu bouges ?",
    ),
    [
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
